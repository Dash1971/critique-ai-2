import XCTest
@testable import CritiqueCore

final class HomeRoutineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10))! }

    func testLegacyBackupStillLoadsWithoutPlanOrAIProvenance() throws {
        var state = AppState(); state.habits = [Habit(title: "Existing habit")]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Database.encode(state)) as? [String: Any])
        json.removeValue(forKey: "dailyRoutine")
        var habits = try XCTUnwrap(json["habits"] as? [[String: Any]])
        habits[0].removeValue(forKey: "aiGenerated"); json["habits"] = habits
        let loaded = try Database.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(loaded.dailyRoutine); XCTAssertNil(loaded.habits[0].aiGenerated)
        XCTAssertEqual(loaded.habits[0].title, "Existing habit")
    }

    func testProposalSchedulingPersistsWithoutInventingCompletionsAndRejectsDuplicates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic.sqlite")
        var state = AppState()
        let proposal = DailyRoutineSuggestion(title: "Try a short planning session.", proposedMinutes: 10)
        state.dailyRoutine = DailyRoutinePlan(suggestions: [proposal], now: now, calendar: calendar)
        let db = try Database(url: url); try db.save(state)
        XCTAssertEqual(state.xp, 0); XCTAssertEqual(state.stats(on: now, calendar: calendar).dueHabits, 0)
        try state.scheduleRoutineSuggestion(proposal.id, title: "Plan the day", minute: 11 * 60, weekdays: [3], now: now, calendar: calendar)
        try db.save(state)
        var loaded = try Database(url: url).load()
        XCTAssertEqual(loaded.dailyRoutine, state.dailyRoutine)
        XCTAssertEqual(loaded.habits.count, 1); XCTAssertEqual(loaded.habits[0].aiGenerated, true)
        XCTAssertTrue(loaded.habits[0].completed.isEmpty); XCTAssertEqual(loaded.xp, 0)
        XCTAssertEqual(loaded.stats(on: now, calendar: calendar).doneHabits, 0)
        XCTAssertEqual(loaded.stats(on: now, calendar: calendar).dueHabits, 1)
        XCTAssertEqual(loaded.dailyRoutine?.suggestions[0].scheduledHabitID, loaded.habits[0].id)
        XCTAssertThrowsError(try loaded.scheduleRoutineSuggestion(proposal.id, title: "Duplicate", minute: 700, weekdays: [3], now: now, calendar: calendar))
        loaded.habits.removeAll()
        XCTAssertThrowsError(try loaded.scheduleRoutineSuggestion(proposal.id, title: "Deleted original", minute: 700, weekdays: [3], now: now, calendar: calendar))
        XCTAssertEqual(try db.recoverySnapshot()?.habits.count, 0)
    }

    func testExpiredAndInvalidSchedulesDoNotMutateRecords() throws {
        var state = AppState()
        let suggestion = DailyRoutineSuggestion(title: "Plan a short walk.")
        state.dailyRoutine = DailyRoutinePlan(suggestions: [suggestion], now: now, calendar: calendar)
        let baseline = state
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertThrowsError(try state.scheduleRoutineSuggestion(suggestion.id, title: "Walk", minute: 700, weekdays: [3], now: tomorrow, calendar: calendar))
        XCTAssertThrowsError(try state.scheduleRoutineSuggestion(suggestion.id, title: "Walk", minute: 1440, weekdays: [3], now: now, calendar: calendar))
        XCTAssertThrowsError(try state.scheduleRoutineSuggestion(suggestion.id, title: "Walk", minute: 700, weekdays: [], now: now, calendar: calendar))
        var differentZone = calendar; differentZone.timeZone = TimeZone(secondsFromGMT: 3600)!
        XCTAssertFalse(state.dailyRoutine!.isCurrent(at: now, calendar: differentZone))
        XCTAssertEqual(state, baseline)
    }

    func testUpcomingActivitiesUseOnlyFutureSavedSchedulesAndUnfinishedGoals() throws {
        var state = AppState()
        var habit = Habit(title: "Future habit"); habit.created = now; habit.weekdays = [3]; habit.reminderMinute = 12 * 60
        var completed = habit; completed.id = UUID(); completed.title = "Already done"; completed.completed = [Day.key(now, calendar: calendar)]
        var anytime = habit; anytime.id = UUID(); anytime.reminderMinute = nil
        var past = habit; past.id = UUID(); past.reminderMinute = 9 * 60
        state.habits = [completed, anytime, past, habit]
        var routine = Routine(title: "Later workout"); routine.weekdays = [3]; routine.reminderMinute = 13 * 60
        state.routines = [routine]
        var goal = Goal(title: "Tomorrow's deadline"); goal.deadline = now.addingTimeInterval(86400)
        var finished = goal; finished.id = UUID(); finished.updates = [GoalUpdate(value: 1)]
        state.goals = [goal, finished]
        let rows = state.upcomingHomeActivities(now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.title), [habit.title, routine.title, goal.title])
        XCTAssertTrue(rows.allSatisfy { $0.date > now })
    }

    func testInvalidPersistedPlanRejectedBeforeSave() throws {
        var state = AppState()
        state.dailyRoutine = DailyRoutinePlan(suggestions: [DailyRoutineSuggestion(title: "Try a walk.", proposedMinutes: 181)], now: now, calendar: calendar)
        XCTAssertThrowsError(try Validation.check(state))
        state.dailyRoutine?.suggestions = []
        XCTAssertThrowsError(try Validation.check(state))
    }
}
