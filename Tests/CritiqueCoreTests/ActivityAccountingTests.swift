import XCTest
@testable import CritiqueCore

final class ActivityAccountingTests: XCTestCase {
    func testInvalidCalendarKeysAreRejectedRatherThanNormalized() {
        XCTAssertNil(Day.date("2026-02-30"))
        XCTAssertNil(Day.date("2026-13-01"))
        XCTAssertNil(Day.date("2026-1-01"))
        XCTAssertNotNil(Day.date("2024-02-29"))
    }
    func testGoalCompletionDateDoesNotMoveWhenLaterProgressExceedsTarget() {
        var goal = Goal(title: "Read"); goal.target = 2
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var a = GoalUpdate(value: 1); a.date = start
        var b = GoalUpdate(value: 2); b.date = start.addingTimeInterval(86400)
        var c = GoalUpdate(value: 3); c.date = start.addingTimeInterval(172800)
        goal.updates = [c, a, b]
        XCTAssertEqual(goal.progress, 3)
        XCTAssertEqual(goal.completedDate, b.date)
    }
    func testOvernightFocusIsSplitBetweenCalendarDaysWithoutDoubleCounting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        var state = AppState()
        state.focus = [FocusSession(started: midnight.addingTimeInterval(-600), ended: midnight.addingTimeInterval(1200)),
                       FocusSession(started: midnight, ended: midnight.addingTimeInterval(300), kind: "Break")]
        XCTAssertEqual(state.stats(on: midnight.addingTimeInterval(-1), calendar: calendar).focusMinutes, 10)
        XCTAssertEqual(state.stats(on: midnight, calendar: calendar).focusMinutes, 20)
        XCTAssertEqual(state.stats(on: midnight.addingTimeInterval(86400), calendar: calendar).focusMinutes, 0)
    }
    func testMealSnapshotsRemainIndependentOfEditableFoodLibrary() throws {
        var state = AppState()
        var food = Food(name: "Oats"); food.calories = 150; food.protein = 5
        state.foods = [food]
        var meal = Meal(); meal.food = food; meal.servings = 2; state.meals = [meal]
        state.foods[0].calories = 999
        let restored = try Database.decode(Database.encode(state))
        XCTAssertEqual(restored.stats(on: meal.date).calories, 300)
        XCTAssertEqual(restored.stats(on: meal.date).protein, 10)
    }
}
