import Foundation
import CritiqueCore

@MainActor final class TrackerStore: ObservableObject {
    @Published private(set) var state: AppState?
    @Published var error: String?
    @Published private var editorIDs: Set<UUID> = []
    var hasPresentedEditor: Bool { !editorIDs.isEmpty }
    func registerEditor(_ id: UUID) { if !editorIDs.contains(id) { editorIDs.insert(id) } }
    func unregisterEditor(_ id: UUID) { editorIDs.remove(id) }
    private var database: Database?

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            // UI checks use an independent persistent store and never reset or
            // open the normal installation's data.
            let filename = CommandLine.arguments.contains("--ui-testing") ? "UITest-state.sqlite" : "state.sqlite"
            let database = try Database(url: directory.appendingPathComponent("CritiqueAI2/\(filename)"))
            var loaded = try database.load()
            if let timer = loaded.timer, timer.deadline <= Date() {
                loaded.settleTimer(); try database.save(loaded)
            }
            self.database = database; state = loaded
            let snapshot = loaded
            Task { await ReminderCoordinator.shared.refresh(snapshot) }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func change(_ action: (inout AppState) throws -> Void) -> Bool {
        guard var updated = state, let database else {
            error = "Saved data is unavailable. Changes have not been written."; return false
        }
        do {
            try action(&updated)
            try database.save(updated)
            state = updated
            let snapshot = updated
            Task { await ReminderCoordinator.shared.refresh(snapshot) }
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
