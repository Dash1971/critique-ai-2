import Foundation

/// Saved-record totals, not an assessment of real-world activity or progress.
/// Today is excluded so neither window includes an incomplete calendar day.
public struct PeriodComparison: Encodable {
    public struct Window: Encodable {
        public let startDay: String
        public let endDayExclusive: String
        public let calendarDays: Int
        public let elapsedHours: Double
        public let scheduledHabitOccurrences: Int
        public let recordedHabitCompletions: Int
        public let recordedWorkouts: Int
        public let recordedWorkoutMinutes: Double
        public let recordedFocusMinutes: Double
    }
    public let previous: Window
    public let recent: Window
    public let timezone: String
    public let scope = "Saved records only; missing records do not establish inactivity. Habit schedules are reconstructed from current saved habits, not historical schedule versions or deleted habits. Equal calendar-day windows may have different elapsed hours around daylight saving. These totals do not establish overall improvement or decline."
}

public extension AppState {
    func completedPeriodComparison(days: Int = 7, now: Date = Date(), calendar: Calendar = .current) throws -> PeriodComparison {
        let cutoff = calendar.startOfDay(for: now)
        guard (1...31).contains(days),
              let recentStart = calendar.date(byAdding: .day, value: -days, to: cutoff),
              let previousStart = calendar.date(byAdding: .day, value: -days, to: recentStart)
        else { throw DataError.invalid("Select between 1 and 31 completed calendar days.") }
        func window(start: Date, end: Date) -> PeriodComparison.Window {
            let dates = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            var scheduled = 0
            var completed = 0
            for day in dates {
                let due = habits.filter { $0.scheduled(on: day, calendar: calendar) }
                scheduled += due.count
                completed += due.filter { $0.completed.contains(Day.key(day, calendar: calendar)) }.count
            }
            let selectedWorkouts = workouts.filter { $0.date >= start && $0.date < end }
            let focusMinutes = focus.filter { $0.kind == "Work" && $0.ended > $0.started }.reduce(0.0) {
                $0 + max(0, min(end, $1.ended).timeIntervalSince(max(start, $1.started))) / 60
            }
            return .init(startDay: Day.key(start, calendar: calendar), endDayExclusive: Day.key(end, calendar: calendar),
                calendarDays: days, elapsedHours: end.timeIntervalSince(start) / 3600,
                scheduledHabitOccurrences: scheduled, recordedHabitCompletions: completed,
                recordedWorkouts: selectedWorkouts.count,
                recordedWorkoutMinutes: selectedWorkouts.reduce(0) { $0 + $1.minutes },
                recordedFocusMinutes: focusMinutes)
        }
        return PeriodComparison(previous: window(start: previousStart, end: recentStart),
            recent: window(start: recentStart, end: cutoff), timezone: calendar.timeZone.identifier)
    }
}
