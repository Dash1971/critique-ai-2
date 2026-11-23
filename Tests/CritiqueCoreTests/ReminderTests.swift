import XCTest
@testable import CritiqueCore

final class ReminderTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8))! }
    func habit(_ title: String = "Private habit") -> Habit {
        var value = Habit(title: title); value.created = calendar.startOfDay(for: now); value.reminderMinute = 9 * 60; return value
    }
    func testDisabledNotificationsDoNotProduceRequests() {
        var state = AppState(); state.habits = [habit()]; state.timer = RunningTimer(minutes: 5, kind: "Work", now: now)
        XCTAssertTrue(state.reminderPlan(now: now, calendar: calendar).requests.isEmpty)
    }
    func testSameTimeHabitsAreConsolidatedAndPrivateTitlesStayOffLockScreen() {
        var state = AppState(); state.habits = [habit("Sensitive title"), habit("Another private title")]
        state.settings.notifications = [ReminderKind.habits.rawValue]
        let plan = state.reminderPlan(now: now, calendar: calendar)
        XCTAssertEqual(plan.requests.count, 8)
        XCTAssertEqual(Set(plan.requests.map(\.date)).count, 8)
        XCTAssertFalse(plan.requests.contains { $0.body.contains("Sensitive") || $0.body.contains("private title") })
        XCTAssertTrue(plan.requests.allSatisfy { $0.date > now })
    }
    func testCompletedHabitAndCancelledTimerAreRemovedFromPlan() {
        var state = AppState(); var value = habit(); value.completed = [Day.key(now, calendar: calendar)]
        state.habits = [value]; state.settings.notifications = [ReminderKind.habits.rawValue, ReminderKind.focus.rawValue]
        state.timer = RunningTimer(minutes: 5, kind: "Work", now: now)
        XCTAssertTrue(state.reminderPlan(now: now, calendar: calendar).requests.contains { $0.isTimer })
        state.settleTimer(now: now, cancel: true)
        let plan = state.reminderPlan(now: now, calendar: calendar)
        XCTAssertFalse(plan.requests.contains { $0.isTimer })
        XCTAssertFalse(plan.requests.contains { calendar.isDate($0.date, inSameDayAs: now) })
    }
    func testGoalDeadlinesUseLocalMorningAndSkipCompletedGoals() {
        var state = AppState(); var goal = Goal(title: "Project")
        goal.deadline = calendar.date(byAdding: .day, value: 2, to: now)!
        state.goals = [goal]; state.settings.notifications = [ReminderKind.goals.rawValue]
        let plan = state.reminderPlan(now: now, calendar: calendar)
        XCTAssertEqual(plan.requests.map { calendar.component(.hour, from: $0.date) }, [9, 9])
        XCTAssertEqual(plan.requests.map { calendar.component(.day, from: $0.date) }, [24, 25])
        state.goals[0].updates = [GoalUpdate(value: 1)]
        XCTAssertTrue(state.reminderPlan(now: now, calendar: calendar).requests.isEmpty)
    }
    func testRollingBatchKeepsSoonestRequestsAndReportsOmissions() {
        var state = AppState(); state.habits = [habit()]; state.settings.notifications = Set(ReminderKind.allCases.map(\.rawValue))
        state.timer = RunningTimer(minutes: 1, kind: "Work", now: now)
        let plan = state.reminderPlan(now: now, calendar: calendar, capacity: 3)
        XCTAssertEqual(plan.requests.count, 3)
        XCTAssertTrue(plan.requests.first!.isTimer)
        XCTAssertEqual(plan.requests.map(\.date), plan.requests.map(\.date).sorted())
        XCTAssertGreaterThan(plan.additionalUpcomingCount, 0)
    }
    func testNonexistentDaylightSavingReminderTimeMovesToNextValidTime() {
        var zoneCalendar = Calendar(identifier: .gregorian); zoneCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = zoneCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        var value = Habit(title: "Stretch"); value.created = date; value.reminderMinute = 150
        var state = AppState(); state.habits = [value]; state.settings.notifications = [ReminderKind.habits.rawValue]
        let request = state.reminderPlan(now: date, calendar: zoneCalendar).requests.first!
        XCTAssertEqual(Day.key(request.date, calendar: zoneCalendar), "2026-03-08")
        XCTAssertEqual(zoneCalendar.component(.hour, from: request.date), 3)
    }
}
