import XCTest
@testable import CritiqueCore

final class WorkoutWorkflowTests: XCTestCase {
    func testWorkoutEditsPreserveRunningTimerAndSettlementAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.sqlite")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for kind in ["Work", "Break"] {
            let database = try Database(url: url)
            var state = AppState()
            var workout = Workout(title: "Synthetic session")
            workout.date = start
            state.workouts = [workout]
            let timer = RunningTimer(minutes: 2, kind: kind, now: start)
            state.timer = timer
            try database.save(state)

            var edited = try Database(url: url).load()
            edited.workouts[0].minutes = 45
            edited.settleTimer(now: timer.deadline.addingTimeInterval(-1))
            try database.save(edited)
            XCTAssertEqual(try database.load().timer, timer)
            XCTAssertTrue(try database.load().focus.isEmpty)

            var expired = try Database(url: url).load()
            expired.settleTimer(now: timer.deadline)
            try database.save(expired)
            var reopened = try Database(url: url).load()
            XCTAssertNil(reopened.timer)
            XCTAssertEqual(reopened.focus.count, 1)
            XCTAssertEqual(reopened.focus.first?.kind, kind)
            XCTAssertEqual(reopened.focus.first?.seconds, 120)
            XCTAssertEqual(reopened.workouts, edited.workouts)
            let settled = reopened
            reopened.settleTimer(now: timer.deadline.addingTimeInterval(600))
            XCTAssertEqual(reopened, settled)
            let recovery = try XCTUnwrap(database.recoverySnapshot())
            XCTAssertEqual(recovery.timer, timer)
            XCTAssertEqual(recovery.workouts, edited.workouts)
            XCTAssertTrue(recovery.focus.isEmpty)
        }
    }

    func testRoutineChangesAndDeletionPreserveRecordedExerciseAcrossReopenAndRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.sqlite")
        var database: Database? = try Database(url: url)
        var exercise = Exercise(name: "Synthetic squat")
        exercise.weight = 12; exercise.sets = 3; exercise.reps = 8
        var routine = Routine(title: "Synthetic routine"); routine.exercises = [exercise]
        var recorded = Workout(title: routine.title)
        recorded.date = Date(timeIntervalSince1970: 1_800_000_000)
        recorded.exercises = routine.exercises
        var earlier = Workout(title: "Earlier session")
        earlier.date = recorded.date.addingTimeInterval(-86400)
        var state = AppState(); state.routines = [routine]; state.workouts = [earlier, recorded]
        try database!.save(state)
        state.routines[0].title = "Revised routine"
        state.routines[0].weekdays = [2, 4]
        state.routines[0].exercises[0].weight = 40
        try database!.save(state)
        database = nil
        database = try Database(url: url)
        var reopened = try database!.load()
        XCTAssertEqual(reopened.routines[0].title, "Revised routine")
        XCTAssertEqual(reopened.routines[0].weekdays, [2, 4])
        XCTAssertEqual(reopened.workouts, [earlier, recorded])
        XCTAssertEqual(reopened.workouts[1].volume, 288)
        reopened.routines.removeAll { $0.id == routine.id }
        try database!.save(reopened)
        database = nil
        let final = try Database(url: url)
        XCTAssertTrue(try final.load().routines.isEmpty)
        XCTAssertEqual(try final.load().workouts, [earlier, recorded])
        let recovery = try XCTUnwrap(final.recoverySnapshot())
        XCTAssertEqual(recovery.routines[0].exercises[0].weight, 40)
        XCTAssertEqual(recovery.workouts, [earlier, recorded])
        let restored = try final.restoreRecoverySnapshot()
        XCTAssertEqual(restored.workouts, [earlier, recorded])
        XCTAssertEqual(restored.routines[0].weekdays, [2, 4])
    }
}
