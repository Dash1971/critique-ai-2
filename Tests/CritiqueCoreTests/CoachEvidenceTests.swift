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
    func testLatestWorkoutUsesOnlySelectedSavedExercisesWithExplicitBounds() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        var state = AppState()
        var earlier = Workout(title: "Earlier"); earlier.date = now.addingTimeInterval(-3600)
        var latest = Workout(title: String(repeating: "w", count: 100)); latest.date = now
        latest.notes = "PRIVATE_NOTES"
        latest.exercises = (0..<5).map { index in
            var exercise = Exercise(name: String(repeating: "e", count: 100))
            exercise.sets = index + 1; exercise.reps = 8; exercise.weight = 12.5; exercise.minutes = 4
            return exercise
        }
        var future = Workout(title: "FUTURE_WORKOUT"); future.date = now.addingTimeInterval(1)
        var old = Workout(title: "OUTSIDE_WINDOW"); old.date = now.addingTimeInterval(-8 * 86400)
        var routine = Routine(title: "UNPERFORMED_TEMPLATE"); routine.exercises = latest.exercises
        state.workouts = [earlier, future, old, latest]; state.routines = [routine]
        let data = try object(state, now: now)
        let workout = try XCTUnwrap(data["latestWorkout"] as? [String: Any])
        XCTAssertEqual(workout["date"] as? String, "2026-11-23")
        XCTAssertEqual((workout["title"] as? String)?.count, 60)
        XCTAssertEqual(workout["omittedExercises"] as? Int, 2)
        let exercises = try XCTUnwrap(workout["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.count, 3)
        XCTAssertEqual((exercises[0]["name"] as? String)?.count, 60)
        XCTAssertEqual(exercises[0]["sets"] as? Int, 1)
        XCTAssertEqual(exercises[0]["reps"] as? Int, 8)
        XCTAssertEqual(exercises[0]["kilograms"] as? Double, 12.5)
        XCTAssertEqual(exercises[0]["minutes"] as? Double, 4)
        XCTAssertEqual(data["recordedWorkouts"] as? Int, 2)
        let context = try state.coachFactContext(now: now, calendar: calendar)
        let fact = try XCTUnwrap(context.facts.first { $0.id == "latest_workout" })
        XCTAssertTrue(fact.text.contains("saved sets 1, reps 8, kg 12.5, minutes 4"))
        XCTAssertTrue(fact.text.contains("Omitted exercises: 2"))
        let json = String(decoding: try context.inferenceJSON(), as: UTF8.self)
        for privateText in ["PRIVATE_NOTES", "UNPERFORMED_TEMPLATE", "FUTURE_WORKOUT", "OUTSIDE_WINDOW"] {
            XCTAssertFalse(json.contains(privateText))
        }
    }
    func testNoSavedWorkoutDoesNotTurnRoutineIntoWorkoutEvidence() throws {
        let now = Date(); var state = AppState(); state.routines = [Routine(title: "Template")]
        XCTAssertNil(try object(state, now: now)["latestWorkout"])
        XCTAssertFalse(try state.coachFactContext(now: now).facts.contains { $0.id == "latest_workout" })
    }

}
