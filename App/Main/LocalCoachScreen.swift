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
struct CheckedRun { let text: String; let metrics: cr_metrics; let suggestions: [CoachAction] }

/// All model ownership and mutation stays on the serial queue. The lock guards
/// only cancellation/pointer lifetime; it is never held during inference.
final class ModelWorker: @unchecked Sendable {
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
    func run(question: String, context: CoachFactContext, completion: @escaping (Result<CheckedRun, Error>) -> Void) {
        lock.lock(); cancelRequested = false; lock.unlock()
        queue.async {
            do {
                guard let coachSystem else { throw EvaluationFailure(message: "The bundled coach policy is missing.") }
                try CoachScopePolicy.requireSupported(question)
                let fixtureContext = context
                let fixture = String(decoding: try context.inferenceJSON(), as: UTF8.self)
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
                completion(.success(CheckedRun(text: checked.displayText, metrics: metrics, suggestions: checked.suggestions)))
            } catch { completion(.failure(error)) }
        }
    }
}

private enum CoachEvidenceMode: String, CaseIterable {
    case snapshot, completedPeriods = "completed_periods"
    var title: String { self == .snapshot ? "Snapshot" : "Completed periods" }
    func context(_ state: AppState, days: Int) throws -> CoachFactContext {
        switch self {
        case .snapshot: return try state.coachFactContext(days: days)
        case .completedPeriods: return try state.coachComparisonFactContext(days: days)
        }
    }
}

@MainActor private final class LocalCoachModel: ObservableObject {
    @Published var question = "Suggest two small improvements based only on my recorded habits."
    @Published var answer = ""
    @Published var status = "Ready. Uses selected saved records from this device."
    @Published var running = false
    @Published var report = "No measurements yet."
    @Published var exportURL: URL?
    private let worker = ModelWorker()
    private let memory = FootprintSampler()
    private var idleTask: Task<Void, Never>?
    private var runID = UUID()
    private var firstDeliveredSeconds: Double?
    private var cancelledByUser = false
    private var activeEvidenceMode = CoachEvidenceMode.snapshot
    private func smokeOutcome(_ outcome: String, error: Error? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("--local-coach-smoke") else { return }
        var record: [String: Any] = ["outcome": outcome, "model_sha256": modelSpec?.sha256 ?? "unavailable",
                                     "measured_at_utc": ISO8601DateFormatter().string(from: Date())]
        if let error { record["reason"] = (error is DataError || error is EvaluationFailure) ? error.localizedDescription : "File or runtime operation failed." }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-coach-smoke-outcome.json")
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
    func run(state: AppState, days: Int, mode: CoachEvidenceMode, onAccepted: @escaping (String, String) -> Bool) {
        guard !running, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard question.count <= 4000 else { status = "Please shorten your question so it fits the on-device context."; return }
        let preparedContext: CoachFactContext
        do { preparedContext = try mode.context(state, days: days) } catch { status = error.localizedDescription; return }
        let asked = question
        activeEvidenceMode = mode
        idleTask?.cancel(); running = true; answer = ""; status = "Verifying/loading local model…"; exportURL = nil
        firstDeliveredSeconds = nil
        cancelledByUser = false
        smokeOutcome("running")
        memory.start()
        let requestStarted = ProcessInfo.processInfo.systemUptime
        let id = UUID(); runID = id
        worker.run(question: question, context: preparedContext, completion: { result in
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
                    self.status = "Finished locally. Recorded facts and generated text are labeled separately."
                    let requestSeconds = ProcessInfo.processInfo.systemUptime - requestStarted
                    self.report = String(format: "Recorded model load: %.2f s\nFirst token (after load): %.2f s\nRequest including load/hash: %.2f s\nGeneration: %.2f s\nPrompt: %d tokens · Output: %d tokens", m.load_seconds, m.first_token_seconds, requestSeconds, m.total_seconds, m.prompt_tokens, m.generated_tokens)
                    if let bytes = observation.peakBytes {
                        self.report += "\nSampled process footprint: " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
                    }
                    self.export(m, requestSeconds: requestSeconds, memory: observation)
                    if !onAccepted(asked, checked.text) { self.status += " Response history could not be saved." }
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
    func evidenceChanged(_ message: String) {
        answer = ""
        if running { cancel() } else { status = message }
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
            "evaluation_only": true, "synthetic_fixture": false, "test_store": ProcessInfo.processInfo.arguments.contains("--ui-testing"), "measured_at_utc": ISO8601DateFormatter().string(from: Date()),
            "hardware": hardware(), "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "model_name": modelSpec?.name ?? "Unavailable",
            "model_sha256": modelSpec?.sha256 ?? "Unavailable",
            "thinking_open_token_suppressed": m.thinking_open_token_suppressed,
            "coach_policy_sha256": coachSystem.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "Unavailable",
            "runtime_source_revision": "44d50873b56b568c28ef2ad8d6445069feaa9fbd",
            "backend_requested": backendRequested,
            "context_tokens": 2048, "max_output_tokens": 256, "constrained_json": m.constrained_json,
            "evidence_mode": activeEvidenceMode.rawValue,
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(Day.key(Date()).replacingOccurrences(of: "-", with: "") + "_v0_local_coach_metrics.json")
            try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            exportURL = url
        } catch { report += "\nMetrics export failed: \(error.localizedDescription)" }
    }
}


struct LocalCoachScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @StateObject private var model = LocalCoachModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var days = 7
    @State private var mode = CoachEvidenceMode.snapshot
    @State private var previewExpanded = false
    @State private var smokeStarted = false
    var body: some View {
        Form {
            Section {
                Text("Offline activity coach").font(.headline)
                Text("Uses your selected saved records. Coaching runs on this device; no activity data is sent to an AI provider. This coach is still experimental.").font(.caption).foregroundStyle(.secondary)
                Picker("Evidence mode", selection: $mode) {
                    ForEach(CoachEvidenceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).disabled(model.running)
                Text(mode == .snapshot ? "Snapshot includes today up to now." : "Completed periods compare two adjacent windows and exclude today.").font(.caption)
                Picker("Record window", selection: $days) {
                    Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                }.disabled(model.running)
                Text("Individual detail is bounded to fit the local model. Missing entries are not proof that an activity did not happen.").font(.caption).foregroundStyle(.secondary)
                Text("Ask a complete question. Earlier messages are saved for reference but are not included in a new request.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("App-calculated evidence", isExpanded: $previewExpanded) {
                    Text("Calculated from saved records, not a generated coach response.").font(.caption)
                    if let state = store.state, let context = try? mode.context(state, days: days) {
                        ForEach(context.facts) { fact in
                            Text(fact.text).font(.caption).textSelection(.enabled).accessibilityIdentifier("coach-evidence-" + fact.id)
                        }
                    } else { Text("Evidence is unavailable. No records have been changed.") }
                }
            }
            Section("Ask about your activities") {
                TextField("Question", text: $model.question, axis: .vertical).lineLimit(2...5).disabled(model.running)
                Button("Ask coach", action: request).disabled(model.running || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.running { ProgressView(); Button("Cancel", action: model.cancel) }
                Text(model.status).font(.caption)
            }
            if !model.answer.isEmpty {
                Section("Coach response") { Text(model.answer).textSelection(.enabled) }
            }
            Section {
                NavigationLink("Local model and diagnostics") { LocalCoachDetails(model: model) }
            }
            if let history = store.state?.coach, !history.isEmpty {
                Section("Saved coaching history") {
                    ForEach(history.reversed()) { message in
                        DisclosureGroup {
                            Text(message.content).textSelection(.enabled)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(message.role == "user" ? "Your question" : "Coach response")
                                Text(message.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Coach")
            .onChange(of: days) { _, _ in model.evidenceChanged("Record window changed. Ask again for updated coaching.") }
            .onChange(of: mode) { _, _ in model.evidenceChanged("Evidence mode changed. Ask again for updated coaching.") }
            .onChange(of: store.state) { old, new in
                guard let old, let new else { return }
                if old.habits != new.habits || old.workouts != new.workouts || old.goals != new.goals || old.meals != new.meals || old.water != new.water || old.focus != new.focus {
                    model.answer = ""
                    if model.running { model.cancel() } else { model.status = "Records changed. Ask again for updated coaching." }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.release() } else { runSmokeIfReady() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in model.release() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.evidenceChanged("Calendar time changed. Ask again for updated coaching.") }
            .task { runSmokeIfReady() }
    }
    private func runSmokeIfReady() {
        guard scenePhase == .active, !smokeStarted, ProcessInfo.processInfo.arguments.contains("--local-coach-smoke") else { return }
        smokeStarted = true; request()
    }
    private func request() {
        guard let state = store.state else { return }
        model.run(state: state, days: days, mode: mode) { question, response in
            store.change {
                $0.coach.append(CoachMessage(role: "user", content: question))
                $0.coach.append(CoachMessage(role: "assistant", content: response))
            }
        }
    }
}

private struct LocalCoachDetails: View {
    @ObservedObject var model: LocalCoachModel
    var body: some View {
        Form {
            Section("Local model") {
                Text(modelSpec?.name ?? "Model manifest unavailable")
                Text(modelSpec?.quality_status ?? "The local model is not configured.").font(.caption)
                if let spec = modelSpec { LabeledContent("Model file", value: ByteCountFormatter.string(fromByteCount: spec.bytes, countStyle: .file)) }
                Text("No API key, subscription or cloud fallback is used.").font(.caption)
            }
            Section("Scope") {
                Text("Activity ideas and recorded progress, not diagnosis, treatment or restrictive diet prescriptions. The coach cannot upload data or edit/delete saved records.").font(.caption)
                Text("Format checks are not a guarantee of advice quality. Proposed activities are not evidence that you performed them.").font(.caption)
            }
            Section("Device measurements") {
                LabeledContent("Hardware", value: hardware())
                Text(model.report).font(.caption.monospaced())
                Text("The footprint is sampled, not an Instruments-certified peak. A single run does not certify sustained heat or battery behavior.").font(.caption)
                if let url = model.exportURL { ShareLink("Share diagnostics · no prompts or answers", item: url) }
                Button("Release model memory", action: model.release)
            }
        }.navigationTitle("Local model")
    }
}

struct LocalCoachConfiguration: View {
    var body: some View {
        Form {
            Section("Provider") {
                Text("On-device model")
                Text(modelSpec?.name ?? "Model configuration unavailable")
                if let spec = modelSpec { LabeledContent("Bundled weights", value: ByteCountFormatter.string(fromByteCount: spec.bytes, countStyle: .file)) }
                Text(modelSpec?.quality_status ?? "The bundled model must be configured before coaching can run.").font(.caption)
            }
            Section("Privacy and scope") {
                Text("No AI-provider account, API key or server is used. Your profile picture is not included in coaching input. Health prescriptions and app-data changes are outside this coach's scope.").font(.caption)
            }
            Section("Model license") {
                if let url = Bundle.main.url(forResource: "LFM-Open-LICENSE", withExtension: "txt", subdirectory: "ThirdParty"),
                   let text = try? String(contentsOf: url) {
                    NavigationLink("LFM Open License") { ScrollView { Text(text).font(.caption).textSelection(.enabled).padding() }.navigationTitle("Model license") }
                } else { Text("Bundled license text is unavailable in this build.").foregroundStyle(.red) }
            }
        }.navigationTitle("AI configuration")
    }
}
