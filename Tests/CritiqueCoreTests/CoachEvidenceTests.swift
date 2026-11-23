import XCTest
@testable import CritiqueCore

final class CoachEvidenceTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    func object(_ state: AppState, days: Int = 7, now: Date) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: state.coachEvidence(days: days, now: now, calendar: calendar)) as! [String: Any]
    }
    func testSchedulesRespectCreationAndExcludeFutureRecords() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        var state = AppState(); var habit = Habit(title: "Read")
        habit.created = now.addingTimeInterval(-86400)
        habit.completed = ["2026-11-22", "2026-11-24"]
        state.habits = [habit]
        var future = Workout(title: "Future"); future.date = now.addingTimeInterval(3600); state.workouts = [future]
        let data = try object(state, now: now)
        let summary = (data["habits"] as! [[String: Any]])[0]
        XCTAssertEqual(summary["scheduled"] as? Int, 2)
        XCTAssertEqual(summary["recordedCompletions"] as? Int, 1)
        XCTAssertEqual(data["recordedWorkouts"] as? Int, 0)
    }
    func testAbsentProgressAndEmptyLogsAreNotInventedMeasurements() throws {
        let now = Date(); var state = AppState(); var goalRecord = Goal(title: "Goal")
        goalRecord.created = now; state.goals = [goalRecord]
        let data = try object(state, now: now)
        let goal = (data["goals"] as! [[String: Any]])[0]
        XCTAssertNil(goal["recordedProgress"])
        XCTAssertTrue((data["scope"] as! String).contains("do not establish inactivity"))
        XCTAssertNil(data["improvement"]); XCTAssertNil(data["consistency"])
    }
    func testFocusClippedToSelectedPeriodAndNow() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let midnight = calendar.startOfDay(for: now); var state = AppState()
        state.focus = [FocusSession(started: midnight.addingTimeInterval(-300), ended: midnight.addingTimeInterval(600)),
                       FocusSession(started: now.addingTimeInterval(-120), ended: now.addingTimeInterval(600)),
                       FocusSession(started: now, ended: now.addingTimeInterval(300), kind: "Break")]
        let data = try object(state, days: 1, now: now)
        XCTAssertEqual(data["recordedFocusMinutes"] as? Double, 12)
        XCTAssertEqual(data["recordedFocusSessions"] as? Int, 2)
    }
    func testBoundedEvidenceExcludesPrivateAndFreeformFields() throws {
        let now = Date(); var state = AppState(); state.profile.username = "PrivateName"
        state.habits = (0..<20).map { _ in
            var habit = Habit(title: String(repeating: "x", count: 200)); habit.created = now; return habit
        }
        let data = try object(state, now: now)
        XCTAssertEqual((data["habits"] as? [[String: Any]])?.count, 6)
        XCTAssertEqual(data["omittedHabits"] as? Int, 14)
        XCTAssertNil(data["profile"]); XCTAssertNil(data["coach"]); XCTAssertNil(data["notes"])
        XCTAssertThrowsError(try state.coachEvidence(days: 0))
        XCTAssertThrowsError(try state.coachEvidence(days: 32))
    }
}
