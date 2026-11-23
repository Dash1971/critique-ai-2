import XCTest
@testable import CritiqueCore

final class GoalWorkflowTests: XCTestCase {
    func testFractionalTargetsUseTheActualTarget() {
        var goal = Goal(title: "Practice")
        goal.target = 0.5
        XCTAssertEqual(goal.fraction, 0)
        goal.updates = [GoalUpdate(value: 0.25)]
        XCTAssertEqual(goal.fraction, 0.5)
        XCTAssertFalse(goal.completed)
        goal.updates = [GoalUpdate(value: 0.5)]
        XCTAssertEqual(goal.fraction, 1)
        XCTAssertTrue(goal.completed)
        goal.updates = [GoalUpdate(value: 0.75)]
        XCTAssertEqual(goal.fraction, 1)
    }

    func testGoalEditsPreserveHistoryAcrossDatabaseReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.sqlite")
        var database: Database? = try Database(url: url)
        var goal = Goal(title: "Read")
        goal.created = Date(timeIntervalSince1970: 1_800_000_000)
        goal.target = 10
        goal.cadence = "Weekly"
        goal.deadline = Date(timeIntervalSince1970: 2_000_000_000)
        var update = GoalUpdate(value: 3)
        update.date = Date(timeIntervalSince1970: 1_900_000_000)
        goal.updates = [update]
        var state = AppState(); state.goals = [goal]
        try database!.save(state)
        state.goals[0].title = "Read chapters"
        state.goals[0].cadence = "Yearly"
        state.goals[0].deadline.addTimeInterval(86_400)
        state.goals[0].target = 12
        try database!.save(state)
        database = nil
        let reopened = try Database(url: url)
        let restored = try reopened.load()
        XCTAssertEqual(restored.goals, state.goals)
        XCTAssertEqual(restored.goals[0].id, goal.id)
        XCTAssertEqual(restored.goals[0].updates, [update])
        XCTAssertEqual(restored.goals[0].progress, 3)
        XCTAssertEqual(restored.goals[0].fraction, 0.25)
        XCTAssertEqual(try reopened.recoverySnapshot()?.goals, [goal])
    }

    func testProgressCorrectionClearsCompletionUntilNextCrossing() {
        var goal = Goal(title: "Practice"); goal.target = 2
        func update(_ value: Double, _ time: TimeInterval) -> GoalUpdate {
            var result = GoalUpdate(value: value)
            result.date = Date(timeIntervalSince1970: time)
            return result
        }
        let first = update(2, 100)
        let correction = update(1, 200)
        let last = update(3, 300)
        goal.updates = [correction, first]
        XCTAssertFalse(goal.completed)
        XCTAssertNil(goal.completedDate)
        goal.updates.insert(last, at: 0)
        XCTAssertTrue(goal.completed)
        XCTAssertEqual(goal.completedDate, last.date)
        XCTAssertEqual(goal.fraction, 1)
    }
}
