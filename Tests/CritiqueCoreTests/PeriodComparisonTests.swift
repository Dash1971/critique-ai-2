import XCTest
@testable import CritiqueCore

final class PeriodComparisonTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    func testAdjacentWindowsExcludeTodayAndDoNotDoubleCountBoundaryRecords() throws {
        var state = AppState()
        state.workouts = [8, 9, 16, 23, 24].map { day in
            var workout = Workout(title: "Synthetic"); workout.date = date(day); workout.minutes = Double(day); return workout
        }
        let comparison = try state.completedPeriodComparison(now: date(23, hour: 12), calendar: calendar)
        XCTAssertEqual(comparison.previous.startDay, "2026-11-09")
        XCTAssertEqual(comparison.previous.endDayExclusive, comparison.recent.startDay)
        XCTAssertEqual(comparison.recent.startDay, "2026-11-16")
        XCTAssertEqual(comparison.recent.endDayExclusive, "2026-11-23")
        XCTAssertEqual(comparison.previous.recordedWorkouts, 1)
        XCTAssertEqual(comparison.previous.recordedWorkoutMinutes, 9)
        XCTAssertEqual(comparison.recent.recordedWorkouts, 1)
        XCTAssertEqual(comparison.recent.recordedWorkoutMinutes, 16)
        XCTAssertEqual(comparison.previous.calendarDays, comparison.recent.calendarDays)
    }
    func testFocusClipsAtBothWindowBoundariesWithoutBreaksOrReversedSessions() throws {
        var state = AppState(); let boundary = date(16); let cutoff = date(23)
        state.focus = [FocusSession(started: boundary.addingTimeInterval(-300), ended: boundary.addingTimeInterval(600)),
                       FocusSession(started: cutoff.addingTimeInterval(-900), ended: cutoff.addingTimeInterval(1200)),
                       FocusSession(started: boundary, ended: cutoff, kind: "Break"),
                       FocusSession(started: cutoff, ended: boundary)]
        let comparison = try state.completedPeriodComparison(now: date(23, hour: 12), calendar: calendar)
        XCTAssertEqual(comparison.previous.recordedFocusMinutes, 5)
        XCTAssertEqual(comparison.recent.recordedFocusMinutes, 25)
    }
    func testHabitCreationAndCurrentSchedulesAreNotInventedHistoricalActivity() throws {
        var state = AppState(); var habit = Habit(title: "Synthetic")
        habit.created = date(20, hour: 18)
        habit.completed = ["2026-11-09", "2026-11-19", "2026-11-20", "2026-11-23"]
        state.habits = [habit]
        let comparison = try state.completedPeriodComparison(now: date(23, hour: 12), calendar: calendar)
        XCTAssertEqual(comparison.previous.scheduledHabitOccurrences, 0)
        XCTAssertEqual(comparison.previous.recordedHabitCompletions, 0)
        XCTAssertEqual(comparison.recent.scheduledHabitOccurrences, 3)
        XCTAssertEqual(comparison.recent.recordedHabitCompletions, 1)
        XCTAssertTrue(comparison.scope.contains("not historical schedule versions"))
        XCTAssertTrue(comparison.scope.contains("do not establish inactivity"))
    }
    func testCalendarWindowsRespectDaylightSavingAndRejectInvalidLengths() throws {
        var zone = calendar; zone.timeZone = TimeZone(identifier: "America/New_York")!
        let now = zone.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let state = AppState(); let comparison = try state.completedPeriodComparison(now: now, calendar: zone)
        XCTAssertEqual(comparison.recent.startDay, "2026-03-02")
        XCTAssertEqual(comparison.recent.endDayExclusive, "2026-03-09")
        XCTAssertEqual(comparison.previous.elapsedHours, 168)
        XCTAssertEqual(comparison.recent.elapsedHours, 167)
        XCTAssertEqual(comparison.recent.calendarDays, 7)
        XCTAssertEqual(comparison.timezone, "America/New_York")
        XCTAssertThrowsError(try state.completedPeriodComparison(days: 0))
        XCTAssertThrowsError(try state.completedPeriodComparison(days: 32))
        let json = String(decoding: try JSONEncoder().encode(comparison), as: UTF8.self)
        XCTAssertFalse(json.contains("Synthetic"))
        XCTAssertFalse(json.contains("improved"))
    }
}
