import SwiftUI
import CryptoKit
import Darwin
import UIKit
import CritiqueCore

private struct BundledModelSpec: Decodable {
    let name: String
    let filename: String
    let sha256: String
    let bytes: Int64
    let quality_status: String
}
private let modelSpec: BundledModelSpec? = {
    guard let url = Bundle.main.url(forResource: "EvaluationModel", withExtension: "json"),
          let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(BundledModelSpec.self, from: data),
          !value.filename.contains("/"), value.sha256.count == 64 else { return nil }
    return value
}()
private let fixtureContext: CoachFactContext? = {
    let now = Date(); let calendar = Calendar.current
    var state = AppState(); var habit = Habit(title: "Read")
    habit.created = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
    habit.completed = Set((0..<4).map { Day.key(calendar.date(byAdding: .day, value: -$0, to: now)!) })
    state.habits = [habit]
    state.focus = [FocusSession(started: now.addingTimeInterval(-5400), ended: now)]
    var goal = Goal(title: "Read a book"); goal.created = habit.created; state.goals = [goal]
    return try? state.coachFactContext(days: 7, now: now, calendar: calendar)
}()
private let fixture: String? = fixtureContext.flatMap { context in
    (try? context.inferenceJSON()).flatMap { String(data: $0, encoding: .utf8) }
}
private let coachSystem: String? = {
    guard let url = Bundle.main.url(forResource: "CoachPolicy", withExtension: "txt"),
          let value = try? String(contentsOf: url, encoding: .utf8), !value.isEmpty else { return nil }
    return value
}()

private func hardware() -> String {
    var value = utsname(); uname(&value)
    return withUnsafeBytes(of: value.machine) {
        String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
    }
}

private struct EvaluationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct MemoryObservation {
    let peakBytes: UInt64?
    let samples: Int
}
private final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var samples = 0
    // Lifecycle methods are owned by EvaluationModel on the main actor.
    private var timer: DispatchSourceTimer?
    private func sample() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        lock.lock(); peak = max(peak, info.phys_footprint); samples += 1; lock.unlock()
    }
    func start() {
        timer?.cancel()
        lock.lock(); peak = 0; samples = 0; lock.unlock()
        sample()
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "critique.memory-sample", qos: .utility))
        source.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source; source.resume()
    }
    func stop() -> MemoryObservation {
        timer?.cancel(); timer = nil; sample()
        lock.lock(); defer { lock.unlock() }
        return MemoryObservation(peakBytes: samples > 0 ? peak : nil, samples: samples)
    }
}

private final class StreamSink {
    var bytes = Data()
}
private struct CheckedRun { let text: String; let metrics: cr_metrics }

/// All model ownership and mutation stays on the serial queue. The lock guards
/// only cancellation/pointer lifetime; it is never held during inference.
private final class ModelWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "critique.local-coach", qos: .userInitiated)
    private let lock = NSLock()
    private var engine: OpaquePointer?
    private var cancelRequested = false
    func cancel() {
        lock.lock(); cancelRequested = true
        if let engine { cr_cancel(engine) }
        lock.unlock()
    }
    func unload(completion: @escaping () -> Void = {}) {
        queue.async {
            self.lock.lock()
            if let engine = self.engine { cr_destroy(engine); self.engine = nil }
            self.lock.unlock()
            completion()
        }
    }
    func run(question: String, completion: @escaping (Result<CheckedRun, Error>) -> Void) {
        lock.lock(); cancelRequested = false; lock.unlock()
        queue.async {
            do {
                guard let coachSystem else { throw EvaluationFailure(message: "The bundled coach policy is missing.") }
                try CoachScopePolicy.requireSupported(question)
                guard let fixtureContext, let fixture else { throw EvaluationFailure(message: "Synthetic fixture preparation failed.") }
                self.lock.lock(); let current = self.engine; self.lock.unlock()
                if current == nil {
                    guard let spec = modelSpec,
                          let url = Bundle.main.url(forResource: spec.filename, withExtension: nil) else {
                        throw EvaluationFailure(message: "The verified model is missing from this build.")
                    }
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    var hasher = SHA256()
                    while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty { hasher.update(data: block) }
                    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    guard hash == spec.sha256 else { throw EvaluationFailure(message: "Model integrity check failed. No inference was attempted.") }
                    self.lock.lock(); let alreadyCancelled = self.cancelRequested; self.lock.unlock()
                    if alreadyCancelled { throw EvaluationFailure(message: "Cancelled before model load.") }
                    var error = [CChar](repeating: 0, count: 512)
                    #if targetEnvironment(simulator)
                    let useMetal = false
                    #else
                    let useMetal = true
                    #endif
                    guard let loaded = cr_create(url.path, useMetal, &error, error.count) else { throw EvaluationFailure(message: String(cString: error)) }
                    self.lock.lock()
                    if self.cancelRequested { cr_destroy(loaded); self.lock.unlock(); throw EvaluationFailure(message: "Cancelled during model load.") }
                    self.engine = loaded; self.lock.unlock()
                }
                self.lock.lock(); let active = self.engine; let stopped = self.cancelRequested
                if !stopped, let active { cr_prepare(active) }
                self.lock.unlock()
                guard let active, !stopped else { throw EvaluationFailure(message: "Cancelled.") }
                let sink = StreamSink()
                let opaque = Unmanaged.passRetained(sink).toOpaque()
                defer { Unmanaged<StreamSink>.fromOpaque(opaque).release() }
                var metrics = cr_metrics(); var error = [CChar](repeating: 0, count: 512)
                let status = cr_generate_contract(active, coachSystem, question, fixture, 256, { bytes, count, context in
                    guard let bytes, let context else { return }
                    let sink = Unmanaged<StreamSink>.fromOpaque(context).takeUnretainedValue()
                    sink.bytes.append(UnsafeBufferPointer(start: UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: count))
                }, opaque, &metrics, &error, error.count)
                guard status == 0 else { throw EvaluationFailure(message: String(cString: error)) }
                guard !metrics.cancelled, !metrics.reached_limit else { throw EvaluationFailure(message: "Generation cancelled or incomplete. No unchecked answer was displayed.") }
                let checked = try CoachContract.check(sink.bytes, against: fixtureContext)
                let facts = checked.facts.map { "• " + $0.text }.joined(separator: "\n")
                let suggestions = checked.suggestions.map { action in
                    "• " + action.text + (action.proposedMinutes.map { " (Proposed duration: \($0) min.)" } ?? "")
                }.joined(separator: "\n")
                let omitted = checked.rejectedSuggestionCount > 0 ? "\nSome generated suggestions failed validation and were omitted." : ""
                let text = "Recorded facts · app calculated\n" + facts + "\n\nNew proposals · generated\n" + suggestions + omitted
                completion(.success(CheckedRun(text: text, metrics: metrics)))
            } catch { completion(.failure(error)) }
        }
    }
}

@MainActor private final class EvaluationModel: ObservableObject {
    @Published var question = "Suggest two small improvements based only on my recorded habits."
    @Published var answer = ""
    @Published var status = "Ready. Uses a synthetic fixture, not your personal records."
    @Published var running = false
    @Published var report = "No measurements yet."
    @Published var exportURL: URL?
    private let worker = ModelWorker()
    private let memory = FootprintSampler()
    private var idleTask: Task<Void, Never>?
    private var runID = UUID()
    private var firstDeliveredSeconds: Double?
    private var cancelledByUser = false
    private func smokeOutcome(_ outcome: String, error: Error? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("--local-coach-smoke") else { return }
        var record: [String: Any] = ["outcome": outcome, "model_sha256": modelSpec?.sha256 ?? "unavailable",
                                     "measured_at_utc": ISO8601DateFormatter().string(from: Date())]
        if let error {
            record["reason"] = (error is DataError || error is EvaluationFailure) ? error.localizedDescription : "File or runtime operation failed."
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-coach-smoke-outcome.json")
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
    func run() {
        guard !running, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard question.count <= 4000 else { status = "Please keep this evaluation question under 4,000 characters."; return }
        idleTask?.cancel(); running = true; answer = ""; status = "Verifying/loading local model…"; exportURL = nil
        firstDeliveredSeconds = nil
        cancelledByUser = false
        smokeOutcome("running")
        memory.start()
        let requestStarted = ProcessInfo.processInfo.systemUptime
        let id = UUID(); runID = id
        worker.run(question: question, completion: { result in
            Task { @MainActor in
                guard self.runID == id else { return }
                self.running = false
                let observation = self.memory.stop()
                if self.cancelledByUser {
                    self.status = "Cancelled. No unchecked answer was displayed."
                    self.smokeOutcome("cancelled")
                    self.worker.unload(); return
                }
                switch result {
                case .success(let checked):
                    let m = checked.metrics
                    self.answer = checked.text
                    self.firstDeliveredSeconds = ProcessInfo.processInfo.systemUptime - requestStarted
                    self.status = "Finished locally. Format/evidence checks passed; this is not model-quality approval."
                    let requestSeconds = ProcessInfo.processInfo.systemUptime - requestStarted
                    self.report = String(format: "Recorded model load: %.2f s\nFirst token (after load): %.2f s\nRequest including load/hash: %.2f s\nGeneration: %.2f s\nPrompt: %d tokens · Output: %d tokens", m.load_seconds, m.first_token_seconds, requestSeconds, m.total_seconds, m.prompt_tokens, m.generated_tokens)
                    if let bytes = observation.peakBytes {
                        self.report += "\nSampled process footprint: " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
                    }
                    self.export(m, requestSeconds: requestSeconds, memory: observation)
                    self.smokeOutcome("accepted")
                case .failure(let error): self.status = error.localizedDescription; self.smokeOutcome("rejected", error: error)
                }
                self.idleTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    self.worker.unload()
                }
            }
        })
    }
    func cancel() { cancelledByUser = true; worker.cancel(); if running { status = "Cancelling…" } }
    func release() {
        cancel()
        worker.unload {
            Task { @MainActor in if !self.running { self.status = "Model released from memory." } }
        }
    }
    private func export(_ m: cr_metrics, requestSeconds: Double, memory: MemoryObservation) {
        #if targetEnvironment(simulator)
        let backendRequested = "CPU (simulator)"
        #else
        let backendRequested = "Metal (device); offload not independently measured"
        #endif
        let metrics: [String: Any] = [
            "evaluation_only": true, "synthetic_fixture": true,
            "hardware": hardware(), "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "model_name": modelSpec?.name ?? "Unavailable",
            "model_sha256": modelSpec?.sha256 ?? "Unavailable",
            "thinking_open_token_suppressed": m.thinking_open_token_suppressed,
            "coach_policy_sha256": coachSystem.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "Unavailable",
            "runtime_source_revision": "44d50873b56b568c28ef2ad8d6445069feaa9fbd",
            "backend_requested": backendRequested,
            "context_tokens": 2048, "max_output_tokens": 256, "constrained_json": m.constrained_json,
            "load_seconds": m.load_seconds, "first_token_seconds": m.first_token_seconds,
            "first_token_excludes_model_load_and_integrity_check": true,
            "first_checked_answer_seconds_from_request": firstDeliveredSeconds.map { $0 as Any } ?? NSNull(),
            "request_seconds_including_model_load_and_integrity": requestSeconds,
            "generation_seconds": m.total_seconds, "prompt_tokens": m.prompt_tokens,
            "generated_tokens": m.generated_tokens, "cancelled": m.cancelled,
            "reached_limit": m.reached_limit,
            "reasoning_filtered": m.reasoning_filtered,
            "generated_json_bytes": m.visible_bytes,
            "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
            "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "sampled_peak_physical_footprint_bytes": memory.peakBytes.map { $0 as Any } ?? NSNull(),
            "memory_samples": memory.samples, "memory_sampling_interval_seconds": 0.25,
            "memory_measurement": "Sampled task_vm_info.phys_footprint; not an Instruments-certified peak; short spikes may be missed",
            "instruments_peak_certified": false, "cloud_fallback": false
        ]
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("20261123_v0_local_coach_metrics.json")
            try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            exportURL = url
        } catch { report += "\nMetrics export failed: \(error.localizedDescription)" }
    }
}

@main struct LocalCoachEvaluationApp: App {
    var body: some Scene { WindowGroup { EvaluationScreen() } }
}
private struct EvaluationScreen: View {
    @StateObject private var model = EvaluationModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var smokeStarted = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("Brand").resizable().scaledToFit().frame(height: 80).frame(maxWidth: .infinity).accessibilityHidden(true)
                    Text("On-device coach evaluation").font(.headline)
                    Text("Synthetic test data only. This is a model evaluation harness, not the finished Critique AI 2.0 application.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Test device") {
                    LabeledContent("Hardware", value: hardware())
                    LabeledContent("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                    Text(ProcessInfo.processInfo.operatingSystemVersionString).font(.caption)
                }
                Section("Bundled evaluation model") {
                    Text(modelSpec?.name ?? "Missing model manifest")
                    Text(modelSpec?.quality_status ?? "Cannot run without a valid model manifest").font(.caption)
                    if let spec = modelSpec { Text(ByteCountFormatter.string(fromByteCount: spec.bytes, countStyle: .file)).font(.caption) }
                }
                Section("Recorded fixture") { Text("Read: 4 of 7 scheduled completions. Focus: 90 minutes. Workout and nutrition history: unknown.") }
                Section("Ask the local model") {
                    TextField("Question", text: $model.question, axis: .vertical).lineLimit(2...5).disabled(model.running)
                    Button("Run on device", action: model.run).disabled(model.running || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.running { Button("Cancel generation", action: model.cancel) }
                    Button("Release model memory", action: model.release)
                }
                Section("Status") { if model.running { ProgressView() }; Text(model.status) }
                if !model.answer.isEmpty { Section("App facts and generated proposals · under review") { Text(model.answer).textSelection(.enabled) } }
                Section("Measurements") {
                    Text(model.report).font(.caption.monospaced())
                    Text("Memory peak, sustained heat/battery, coaching quality and physical-device acceptance are not certified by this single run.").font(.caption).foregroundStyle(.secondary)
                    if let url = model.exportURL { ShareLink("Share metrics (no prompts or answers)", item: url) }
                }
            }
            .navigationTitle("Critique AI 2.0")
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.release() } else { runSmokeIfReady() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in model.release() }
        .task { runSmokeIfReady() }
    }
    private func runSmokeIfReady() {
        guard scenePhase == .active, !smokeStarted, ProcessInfo.processInfo.arguments.contains("--local-coach-smoke") else { return }
        smokeStarted = true; model.run()
    }
}
