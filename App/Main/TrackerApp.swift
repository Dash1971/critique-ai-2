import SwiftUI
import CritiqueCore
import Charts
import PhotosUI
import UniformTypeIdentifiers

@main struct CritiqueAI2App: App {
    @StateObject private var store = TrackerStore()
    @Environment(\.scenePhase) private var scenePhase
    init() { ForegroundReminderPresentation.install() }
    var body: some Scene {
        WindowGroup {
            TrackerRoot().environmentObject(store)
                .preferredColorScheme(store.state?.settings.theme == "Light" ? .light : .dark)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.resume() } }
        }
    }
}

private enum Destination: String, CaseIterable, Identifiable, Hashable {
    case today = "Today", habits = "Habits", goals = "Goals", activity = "Activity", coach = "Coach"
    var id: String { rawValue }
    var icon: String {
        switch self { case .today: return "square.grid.2x2"; case .habits: return "checkmark.circle"; case .goals: return "target"; case .activity: return "figure.run"; case .coach: return "bubble.left.and.bubble.right" }
    }
}
private struct TrackerRoot: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var selected: Destination? = .today
    @State private var preferences = false
    var body: some View {
        Group {
            if store.state == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView("Saved data could not be opened", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(store.error ?? "No changes have been written."))
                    Button("Try again") { store.reload() }
                    PreviousSaveRecoveryButton()
                    BackupRestoreButton()
                    Text("No records are replaced unless you confirm a restore. If storage itself cannot be opened, restore is unavailable until it can be opened again.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            } else if horizontalSize == .compact {
                TabView(selection: Binding(get: { selected ?? .today }, set: { selected = $0 })) {
                    ForEach(Destination.allCases) { destination in
                        NavigationStack { page(destination).toolbar { settingsButton } }
                            .tabItem { Label(destination.rawValue, systemImage: destination.icon) }
                            .tag(destination)
                    }
                }
            } else {
                NavigationSplitView {
                    List(Destination.allCases, selection: $selected) { destination in
                        Label(destination.rawValue, systemImage: destination.icon).tag(destination)
                    }.navigationTitle("Critique AI 2.0")
                } detail: { NavigationStack { page(selected ?? .today).toolbar { settingsButton } } }
            }
        }
        .sheet(isPresented: $preferences) { PreferencesSheet() }
        .onAppear { if ProcessInfo.processInfo.arguments.contains("--local-coach-smoke") { selected = .coach } }
        .alert("Changes were not saved", isPresented: Binding(get: { store.error != nil && store.state != nil && !store.hasPresentedEditor },
            set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } }
            message: { Text(store.error ?? "Please try again.") }
    }
    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { preferences = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
        }
    }
    @ViewBuilder private func page(_ destination: Destination) -> some View {
        switch destination {
        case .today: TodayScreen()
        case .habits: HabitsScreen()
        case .goals: GoalsScreen()
        case .activity: ActivityScreen()
        case .coach: LocalCoachScreen()
        }
    }
}

private struct TodayScreen: View {
    @EnvironmentObject private var store: TrackerStore
    var body: some View {
        ScrollView {
            if let state = store.state {
                let stats = state.stats(on: Date())
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image("Brand").resizable().scaledToFit().frame(width: 76, height: 60).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text("Today").font(.largeTitle.bold())
                            Text(Date(), format: .dateTime.weekday(.wide).month().day()).foregroundStyle(.secondary)
                        }
                    }
                    Text(state.habits.isEmpty ? "Start with one manageable habit." : "Choose one useful action for today.")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("Scheduled habits", value: "\(stats.doneHabits) / \(stats.dueHabits)", icon: "checkmark.circle")
                        metric("Focus logged", value: "\(Int(stats.focusMinutes)) min", icon: "timer")
                        metric("Workouts logged", value: "\(stats.workouts)", icon: "figure.strengthtraining.traditional")
                        metric("Goals completed", value: "\(stats.completedGoals)", icon: "target")
                    }
                    if stats.dueHabits > 0 {
                        ProgressView("Scheduled habit completion", value: stats.completion)
                            .accessibilityValue("\(stats.doneHabits) of \(stats.dueHabits) completed")
                    }
                    GroupBox("Recorded habit completions · last 7 days") {
                        Chart(state.series(days: 7)) { day in
                            BarMark(x: .value("Day", day.day), y: .value("Completions", day.doneHabits))
                                .accessibilityLabel(day.day).accessibilityValue("\(day.doneHabits) completions")
                        }.frame(height: 170).chartXAxis(.hidden)
                    }
                    NavigationLink("Compare recorded periods") { RecordedPeriodComparisonScreen() }
                    HStack {
                        Label("Level \(state.level)", systemImage: "star")
                        Spacer(); Text("\(state.xp) XP").monospacedDigit()
                    }
                    if !state.achievements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Achievements").font(.headline)
                            ForEach(state.achievements, id: \.self) { Label($0, systemImage: "rosette") }
                        }
                    }
                }.padding()
            }
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RecordedPeriodComparisonScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var days = 7
    @State private var snapshotDate = Date()
    @State private var injectedTestSnapshot = false
    var body: some View {
        Form {
            Section {
                Picker("Completed days per period", selection: $days) {
                    Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                }.pickerStyle(.segmented)
                Text("Two completed periods; today is excluded.").font(.caption)
            }
            if let state = store.state,
               let comparison = try? state.completedPeriodComparison(days: days, now: snapshotDate) {
                window(comparison.recent, title: "Recent period")
                window(comparison.previous, title: "Previous period")
                Section("How to read this") {
                    Text("Missing records do not establish inactivity. These are saved totals, not a score of overall improvement.")
                    Text("Habit schedules use current saved habits. Past edits and deleted habits cannot be reconstructed.")
                    Text("Calendar periods may have different elapsed hours around daylight saving.")
                    LabeledContent("Timezone", value: comparison.timezone)
                }.font(.caption)
            } else {
                Text("Recorded periods are unavailable. No records have been changed.")
            }
        }.navigationTitle("Recorded periods")
            .onAppear {
                snapshotDate = Date()
                // A stale clock fixture is isolated to explicit UI-test runs;
                // foreground refresh below always uses the real device clock.
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--ui-testing"), arguments.contains("--ui-testing-stale-comparison"), !injectedTestSnapshot {
                    snapshotDate = Calendar.current.date(byAdding: .day, value: -1, to: snapshotDate) ?? snapshotDate
                    injectedTestSnapshot = true
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { snapshotDate = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in snapshotDate = Date() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in snapshotDate = Date() }
    }
    private func range(_ window: PeriodComparison.Window) -> String {
        let calendar = Calendar.current
        guard let end = Day.date(window.endDayExclusive, calendar: calendar),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: end) else { return window.startDay }
        return "\(window.startDay) through \(Day.key(lastDay, calendar: calendar))"
    }
    private func window(_ value: PeriodComparison.Window, title: String) -> some View {
        Section(title) {
            Text(range(value)).font(.caption).accessibilityIdentifier(title == "Recent period" ? "comparison-recent-range" : "comparison-previous-range")
            LabeledContent("Completed calendar days", value: "\(value.calendarDays)")
            LabeledContent("Habit completions saved", value: "\(value.recordedHabitCompletions) / \(value.scheduledHabitOccurrences) scheduled")
            LabeledContent("Workouts saved", value: "\(value.recordedWorkouts)")
            LabeledContent("Workout minutes saved", value: value.recordedWorkoutMinutes.formatted(.number.precision(.fractionLength(0...1))))
            LabeledContent("Work-focus minutes saved", value: value.recordedFocusMinutes.formatted(.number.precision(.fractionLength(0...1))))
            LabeledContent("Elapsed hours", value: value.elapsedHours.formatted(.number.precision(.fractionLength(0...1))))
        }
    }
}

private struct PreferencesSheet: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var theme = "Dark"
    @State private var draftLoaded = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var backup: JSONBackupDocument?
    @State private var exporting = false
    @State private var reset = false
    var body: some View {
        EditorNavigationStack {
            Form {
                Section("Profile") {
                    TextField("Username", text: $username).textContentType(.nickname)
                    if let photo, let image = UIImage(data: photo) { Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle()).accessibilityLabel("Selected profile picture") }
                    PhotosPicker("Choose profile picture", selection: $photoItem, matching: .images)
                    if photo != nil { Button("Remove picture") { photo = nil } }
                }
                Section("Appearance") { Picker("Theme", selection: $theme) { Text("Dark").tag("Dark"); Text("Light").tag("Light") } }
                Section { NavigationLink("Notifications") { RemindersScreen() } }
                Section { NavigationLink("AI configuration") { LocalCoachConfiguration() } }
                Section("Data") {
                    Button("Export backup") {
                        do {
                            guard let state = store.state else { return }
                            backup = JSONBackupDocument(data: try Database.encode(state)); exporting = true
                        } catch { store.error = error.localizedDescription }
                    }
                    BackupRestoreButton { dismiss() }
                    PreviousSaveRecoveryButton { dismiss() }
                    Button("Reset application data", role: .destructive) { reset = true }
                    Text("Backups contain your activity and profile data. Store them somewhere private. Restore replaces this installation's current records.").font(.caption)
                }
                Section { Text("All tracker data is saved on this device. This is an unfinished development build, not a completed release.").font(.caption) }
            }.navigationTitle("Settings").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ $0.profile.username = username; $0.profile.photo = photo; $0.settings.theme = theme }) { dismiss() }
                } }
            }
            .onAppear {
                guard !draftLoaded else { return }
                username = store.state?.profile.username ?? "You"
                theme = store.state?.settings.theme ?? "Dark"
                photo = store.state?.profile.photo
                draftLoaded = true
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data),
                              let resized = image.preparingThumbnail(of: CGSize(width: 512, height: 512)),
                              let encoded = resized.jpegData(compressionQuality: 0.85) else { return }
                        photo = encoded
                    } catch { store.error = error.localizedDescription }
                }
            }
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                          defaultFilename: "critique-backup-\(Day.key(Date()))") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .confirmationDialog("Reset all application data on this device? Export a backup first if you need these records.", isPresented: $reset, titleVisibility: .visible) {
                Button("Reset all data", role: .destructive) { if store.change({ $0 = AppState() }) { dismiss() } }
            }
        }
    }
}

private struct PreviousSaveRecoveryButton: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var confirming = false
    var onRestored: () -> Void = {}
    var body: some View {
        Button("Restore previous save") { confirming = true }
            .disabled(!store.recoveryAvailable)
            .confirmationDialog("Restore the previous save? This replaces current records with the immediately preceding saved version, not a full backup.",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Restore previous save", role: .destructive) {
                    if store.restorePreviousSave() { onRestored() }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

private struct BackupRestoreButton: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var importing = false
    @State private var restored: AppState?
    var onRestored: () -> Void = {}
    var body: some View {
        Button("Restore backup") { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let allowed = url.startAccessingSecurityScopedResource()
                    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                    restored = try Database.decode(Data(contentsOf: url))
                } catch { store.error = error.localizedDescription }
            }
            .confirmationDialog("Replace current data with this validated backup?", isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } }), titleVisibility: .visible) {
                Button("Replace current data", role: .destructive) {
                    if let value = restored, store.restoreBackup(value) { onRestored() }
                    restored = nil
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

private struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DataError.invalid("Could not read this backup.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
