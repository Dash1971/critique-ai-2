import Foundation
import CritiqueCore

@MainActor final class TrackerStore: ObservableObject {
    @Published private(set) var state: AppState?
    @Published var error: String?
    @Published private(set) var recoveryAvailable = false
    @Published private var editorIDs: Set<UUID> = []
    var hasPresentedEditor: Bool { !editorIDs.isEmpty }
    func registerEditor(_ id: UUID) { if !editorIDs.contains(id) { editorIDs.insert(id) } }
    func unregisterEditor(_ id: UUID) { editorIDs.remove(id) }
    private var database: Database?

    init() { reload() }
    func reload() {
        database = nil
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            // UI checks use an independent persistent store and never reset or
            // open the normal installation's data.
            let testing = CommandLine.arguments.contains("--ui-testing")
            let filename: String
            if !testing { filename = "state.sqlite" }
            else if CommandLine.arguments.contains("--ui-testing-backup-import-fixture") {
                filename = "UITest-backup-import-state.sqlite"
            } else if CommandLine.arguments.contains("--ui-testing-focus-lifecycle-fixture") {
                filename = "UITest-focus-lifecycle-state.sqlite"
            } else if CommandLine.arguments.contains("--ui-testing-comparison-fixture") {
                filename = "UITest-comparison-state.sqlite"
            } else if CommandLine.arguments.contains("--ui-testing-recovery-fixture") {
                filename = "UITest-recovery-state.sqlite"
            } else { filename = "UITest-state.sqlite" }
            let database = try Database(url: directory.appendingPathComponent("CritiqueAI2/\(filename)"))
            // Retain an opened database even if decoding its current row fails,
            // so a validated snapshot or backup can still be restored.
            self.database = database
            var loaded = try database.load()
            if let timer = loaded.timer, timer.deadline <= Date() {
                loaded.settleTimer(); try database.save(loaded)
            }
            accept(loaded)
        } catch {
            state = nil
            self.error = error.localizedDescription
            recoveryAvailable = (try? database?.recoverySnapshot()) != nil
        }
    }
    private func accept(_ saved: AppState) {
        state = saved; error = nil
        recoveryAvailable = (try? database?.recoverySnapshot()) != nil
        Task { await ReminderCoordinator.shared.refresh(saved) }
    }
    @discardableResult func restorePreviousSave() -> Bool {
        guard let database else { error = "Saved data cannot be opened. Try again before restoring."; return false }
        do { accept(try database.restoreRecoverySnapshot()); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func restoreBackup(_ backup: AppState) -> Bool {
        guard let database else { error = "Saved data cannot be opened. Try again before restoring."; return false }
        do { try database.save(backup); accept(backup); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func change(_ action: (inout AppState) throws -> Void) -> Bool {
        guard var updated = state, let database else {
            error = "Saved data is unavailable. Changes have not been written."; return false
        }
        do {
            try action(&updated)
            try database.save(updated)
            accept(updated)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func resume() {
        if let timer = state?.timer, timer.deadline <= Date() { change { $0.settleTimer() } }
        objectWillChange.send()
        if let state { Task { await ReminderCoordinator.shared.refresh(state) } }
    }
    func save(_ habit: Habit) -> Bool {
        change { state in
            if let index = state.habits.firstIndex(where: { $0.id == habit.id }) { state.habits[index] = habit }
            else { state.habits.append(habit) }
        }
    }
    func save(_ goal: Goal) -> Bool {
        change { state in
            if let index = state.goals.firstIndex(where: { $0.id == goal.id }) { state.goals[index] = goal }
            else { state.goals.append(goal) }
        }
    }
}
