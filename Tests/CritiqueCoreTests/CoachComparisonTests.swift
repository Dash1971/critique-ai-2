import XCTest
@testable import CritiqueCore

final class CoachComparisonTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))! }
    func testFactsUseExactCompletedWindowsAndExcludeToday() throws {
        var state = AppState()
        state.workouts = [(-10, 45.0), (-2, 30.0), (0, 100.0)].map { offset, minutes in
            var workout = Workout(title: "Synthetic"); workout.date = calendar.date(byAdding: .day, value: offset, to: now)!
            workout.minutes = minutes; return workout
        }
        let boundary = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        state.focus = [FocusSession(started: boundary.addingTimeInterval(-300), ended: boundary.addingTimeInterval(600))]
        var habit = Habit(title: "Synthetic"); habit.created = now.addingTimeInterval(-30 * 86400)
        habit.completed = ["2026-11-13", "2026-11-21", "2026-11-23"]; state.habits = [habit]
        let facts = try state.coachComparisonFactContext(now: now, calendar: calendar).facts
        let previous = try XCTUnwrap(facts.first { $0.id == "previous_period" }?.text)
        let recent = try XCTUnwrap(facts.first { $0.id == "recent_period" }?.text)
        XCTAssertTrue(previous.contains("2026-11-09 through 2026-11-15"))
        XCTAssertTrue(recent.contains("2026-11-16 through 2026-11-22"))
        XCTAssertTrue(previous.contains("completions: 1 out of 7")); XCTAssertTrue(recent.contains("completions: 1 out of 7"))
        XCTAssertTrue(previous.contains("workouts: 1; workout minutes: 45"))
        XCTAssertTrue(recent.contains("workouts: 1; workout minutes: 30"))
        XCTAssertTrue(previous.contains("work-focus minutes: 5")); XCTAssertTrue(recent.contains("work-focus minutes: 10"))
        XCTAssertFalse(recent.contains("100"))
    }
    func testAggregateInputStaysBoundedAndExcludesTitlesNotesIdentityAndOtherDomains() throws {
        var state = AppState(); state.profile.username = "PRIVATE_IDENTITY"; state.profile.photo = Data([1, 2, 3])
        state.habits = (0..<100).map { _ in
            var habit = Habit(title: "UNTRUSTED_HABIT_TITLE"); habit.created = now.addingTimeInterval(-60 * 86400); return habit
        }
        var workout = Workout(title: "UNTRUSTED_WORKOUT_TITLE"); workout.date = now.addingTimeInterval(-86400)
        workout.notes = "PRIVATE_NOTES"; state.workouts = [workout]
        state.goals = [Goal(title: "PRIVATE_GOAL")]
        let context = try state.coachComparisonFactContext(now: now, calendar: calendar)
        let data = try context.inferenceJSON(); let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(context.facts.count, 4); XCTAssertLessThan(data.count, 4000)
        for excluded in ["PRIVATE_IDENTITY", "UNTRUSTED_HABIT_TITLE", "UNTRUSTED_WORKOUT_TITLE", "PRIVATE_NOTES", "PRIVATE_GOAL", "photo"] {
            XCTAssertFalse(text.contains(excluded))
        }
        XCTAssertEqual(data, try state.coachComparisonFactContext(now: now, calendar: calendar).inferenceJSON())
    }
    func testUnchangedContractAcceptsKnownComparisonIDsWithoutLettingModelHideFacts() throws {
        let context = try AppState().coachComparisonFactContext(now: now, calendar: calendar)
        let payload = Data(#"{"fact_ids":["recent_period"],"suggestions":[{"kind":"planning","text":"Plan a manageable activity for another day."}],"question":null}"#.utf8)
        let reply = try CoachContract.check(payload, against: context)
        XCTAssertEqual(reply.facts, context.facts); XCTAssertEqual(reply.selectedFactIDs, ["recent_period"])
        let unavailable = Data(#"{"fact_ids":["workouts"],"suggestions":[{"kind":"planning","text":"Plan an activity."}]}"#.utf8)
        XCTAssertThrowsError(try CoachContract.check(unavailable, against: context))
    }
    func testMissingDataCaveatsAndSnapshotBehaviorRemainExplicit() throws {
        let state = AppState(); let context = try state.coachComparisonFactContext(now: now, calendar: calendar)
        let limits = try XCTUnwrap(context.facts.first { $0.id == "comparison_limits" }?.text)
        XCTAssertTrue(limits.contains("missing records do not establish inactivity"))
        XCTAssertTrue(limits.contains("not historical schedule versions or deleted habits"))
        XCTAssertTrue(limits.contains("do not establish overall improvement or decline"))
        let snapshot = try state.coachFactContext(now: now, calendar: calendar)
        XCTAssertTrue(snapshot.facts.contains { $0.id == "comparison_limit" })
        XCTAssertFalse(snapshot.facts.contains { $0.id == "previous_period" })
        XCTAssertThrowsError(try state.coachComparisonFactContext(days: 0))
        XCTAssertThrowsError(try state.coachComparisonFactContext(days: 32))
        var invalid = state; var workout = Workout(title: "Synthetic"); workout.date = now.addingTimeInterval(-86400); workout.minutes = .nan
        invalid.workouts = [workout]
        XCTAssertThrowsError(try invalid.coachComparisonFactContext(now: now, calendar: calendar))
    }
    func testDSTHoursAndTimezoneSurviveFactPreparation() throws {
        var zone = calendar; zone.timeZone = TimeZone(identifier: "America/New_York")!
        let date = zone.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let facts = try AppState().coachComparisonFactContext(now: date, calendar: zone).facts
        XCTAssertTrue(facts.contains { $0.id == "comparison_scope" && $0.text.contains("America/New_York") })
        XCTAssertTrue(facts.contains { $0.id == "previous_period" && $0.text.contains("168 elapsed hours") })
        XCTAssertTrue(facts.contains { $0.id == "recent_period" && $0.text.contains("167 elapsed hours") && $0.text.contains("2026-03-02 through 2026-03-08") })
    }
}
