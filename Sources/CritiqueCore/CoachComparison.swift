import Foundation

public extension AppState {
    /// Separate from the today-inclusive snapshot: every comparison fact uses
    /// the same two completed windows, without titles, notes or identity data.
    func coachComparisonFactContext(days: Int = 7, now: Date = Date(), calendar: Calendar = .current) throws -> CoachFactContext {
        let comparison = try completedPeriodComparison(days: days, now: now, calendar: calendar)
        func number(_ value: Double) throws -> String {
            guard value.isFinite, value >= 0 else { throw DataError.invalid("Comparison evidence contains invalid totals.") }
            return NSNumber(value: value).stringValue
        }
        func fact(_ window: PeriodComparison.Window, id: String, label: String) throws -> CoachFact {
            guard let end = Day.date(window.endDayExclusive, calendar: calendar),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: end) else {
                throw DataError.invalid("Comparison evidence contains an invalid date range.")
            }
            let range = "\(window.startDay) through \(Day.key(lastDay, calendar: calendar))"
            return CoachFact(id: id, text: "\(label) completed period: \(range) (\(window.calendarDays) calendar days; \(try number(window.elapsedHours)) elapsed hours). Recorded habit completions: \(window.recordedHabitCompletions) out of \(window.scheduledHabitOccurrences) current-schedule occurrences. Recorded workouts: \(window.recordedWorkouts); workout minutes: \(try number(window.recordedWorkoutMinutes)). Recorded work-focus minutes: \(try number(window.recordedFocusMinutes)).")
        }
        return CoachFactContext(scope: "The app owns these comparison facts. Select relevant fact IDs; do not restate or invent personal facts. Propose activities, not edits to records.", facts: [
            CoachFact(id: "comparison_scope", text: "Two adjacent completed periods in timezone \(comparison.timezone). Today is excluded. Counts describe saved records, not all real-world activity."),
            try fact(comparison.previous, id: "previous_period", label: "Previous"),
            try fact(comparison.recent, id: "recent_period", label: "Recent"),
            CoachFact(id: "comparison_limits", text: comparison.scope)
        ])
    }
}
