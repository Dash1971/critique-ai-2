import Foundation

public enum ReminderKind: String, CaseIterable, Identifiable {
    case habits = "Habits", workouts = "Workouts", goals = "Goals", focus = "Focus"
    case summary = "Daily summary", streak = "Streak check"
    public var id: String { rawValue }
}
public struct PlannedReminder: Identifiable, Equatable {
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
    public let isTimer: Bool
}
public struct ReminderPlan {
    public let requests: [PlannedReminder]
    public let additionalUpcomingCount: Int
}
public extension AppState {
    /// A rolling batch of actual upcoming notifications, refreshed on launch,
    /// foreground and record changes. OS permission/delivery is separate.
    func reminderPlan(now: Date = Date(), calendar: Calendar = .current, capacity: Int = 48) -> ReminderPlan {
        var candidates: [String: PlannedReminder] = [:]
        func enabled(_ kind: ReminderKind) -> Bool { settings.notifications.contains(kind.rawValue) }
        func time(_ minute: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        func add(_ key: String, date: Date, title: String, body: String, timer: Bool = false) {
            guard date > now else { return }
            let id = "critique.reminder." + key
            candidates[id] = PlannedReminder(id: id, date: date, title: title, body: body, isTimer: timer)
        }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let key = Day.key(day, calendar: calendar)
            if enabled(.habits) {
                for habit in habits where habit.scheduled(on: day, calendar: calendar) && !habit.completed.contains(key) {
                    if let minute = habit.reminderMinute, let date = time(minute, on: day) {
                        // Identical-time habit reminders are consolidated without
                        // disclosing habit titles on the lock screen.
                        add("habits.\(key).\(minute)", date: date, title: "Habit reminder", body: "Review your scheduled habits in Critique AI 2.0.")
                    }
                }
            }
            if enabled(.workouts) {
                for routine in routines where routine.weekdays.contains(calendar.component(.weekday, from: day)) {
                    if let minute = routine.reminderMinute, let date = time(minute, on: day) {
                        add("workouts.\(key).\(minute)", date: date, title: "Workout reminder", body: "Review your planned training session in Critique AI 2.0.")
                    }
                }
            }
            if enabled(.summary), let date = time(settings.summaryMinute, on: day) {
                add("summary.\(key)", date: date, title: "Daily progress", body: "Open Critique AI 2.0 to review today's recorded progress.")
            }
            if enabled(.streak), habits.contains(where: { $0.scheduled(on: day, calendar: calendar) && !$0.completed.contains(key) }), let date = time(20 * 60, on: day) {
                add("streak.\(key)", date: date, title: "Habit check-in", body: "Review today's scheduled habits. Only mark activities you actually performed.")
            }
        }
        if enabled(.goals) {
            for goal in goals where !goal.completed {
                let day = calendar.startOfDay(for: goal.deadline)
                if let date = time(9 * 60, on: day) {
                    add("goal.\(goal.id).due", date: date, title: "Goal deadline", body: "A goal reaches its deadline today. Review it in Critique AI 2.0.")
                }
                if let previous = calendar.date(byAdding: .day, value: -1, to: day), let date = time(9 * 60, on: previous) {
                    add("goal.\(goal.id).soon", date: date, title: "Upcoming goal deadline", body: "A goal deadline is approaching. Review your next step in Critique AI 2.0.")
                }
            }
        }
        if enabled(.focus), let timer {
            add("timer", date: timer.deadline, title: "Timer finished", body: "Your scheduled timer reached its deadline. Review the session and take a break if needed.", timer: true)
        }
        let sorted = candidates.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let count = max(0, capacity)
        return ReminderPlan(requests: Array(sorted.prefix(count)), additionalUpcomingCount: max(0, sorted.count - count))
    }
}
