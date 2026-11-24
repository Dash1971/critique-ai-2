import Foundation

/// Generated proposals are separate from scheduled habits and completed activity.
public struct DailyRoutineSuggestion: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var proposedMinutes: Int?
    public var scheduledHabitID: UUID?
    public init(title: String, proposedMinutes: Int? = nil) {
        self.title = title; self.proposedMinutes = proposedMinutes
    }
}

public struct DailyRoutinePlan: Codable, Equatable {
    public var day: String
    public var timezone: String
    public var generatedAt: Date
    public var suggestions: [DailyRoutineSuggestion]
    public init(suggestions: [DailyRoutineSuggestion], now: Date = Date(), calendar: Calendar = .current) {
        day = Day.key(now, calendar: calendar); timezone = calendar.timeZone.identifier
        generatedAt = now; self.suggestions = suggestions
    }
    public func isCurrent(at now: Date, calendar: Calendar = .current) -> Bool {
        day == Day.key(now, calendar: calendar) && timezone == calendar.timeZone.identifier
    }
}

public struct HomeActivity: Identifiable, Equatable {
    public enum Kind: Equatable { case habit, workout, goal }
    public let id: String
    public let title: String
    public let date: Date
    public let kind: Kind
}

public extension AppState {
    /// Only future saved schedules, never model-invented appointments.
    func upcomingHomeActivities(now: Date = Date(), calendar: Calendar = .current) -> [HomeActivity] {
        let key = Day.key(now, calendar: calendar)
        func time(_ minute: Int) -> Date? {
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now)
        }
        var result: [HomeActivity] = habits.compactMap { habit in
            guard habit.scheduled(on: now, calendar: calendar), !habit.completed.contains(key),
                  let minute = habit.reminderMinute, let date = time(minute), date > now else { return nil }
            return HomeActivity(id: "habit-\(habit.id)", title: habit.title, date: date, kind: .habit)
        }
        result += routines.compactMap { routine in
            guard routine.weekdays.contains(calendar.component(.weekday, from: now)),
                  let minute = routine.reminderMinute, let date = time(minute), date > now else { return nil }
            return HomeActivity(id: "routine-\(routine.id)", title: routine.title, date: date, kind: .workout)
        }
        let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        result += goals.compactMap { goal in
            guard !goal.completed, goal.deadline > now, goal.deadline <= end else { return nil }
            return HomeActivity(id: "goal-\(goal.id)", title: goal.title, date: goal.deadline, kind: .goal)
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    /// Explicit user approval creates a habit, not a completion. Repeated saves
    /// cannot create duplicate habits from the same persisted proposal.
    mutating func scheduleRoutineSuggestion(_ id: UUID, title: String, minute: Int,
                                           weekdays: Set<Int>, now: Date = Date(), calendar: Calendar = .current) throws {
        guard var plan = dailyRoutine, plan.isCurrent(at: now, calendar: calendar),
              let index = plan.suggestions.firstIndex(where: { $0.id == id }),
              plan.suggestions[index].scheduledHabitID == nil else {
            throw DataError.invalid("This suggestion has expired or has already been scheduled. Generate a new plan if needed.")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, (0..<1440).contains(minute), !weekdays.isEmpty,
              weekdays.isSubset(of: Set(1...7)) else { throw DataError.invalid("Choose a name, time and scheduled days.") }
        var habit = Habit(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        habit.created = now; habit.category = "AI routine"; habit.aiGenerated = true
        habit.weekdays = weekdays; habit.reminderMinute = minute
        habits.append(habit)
        plan.suggestions[index].scheduledHabitID = habit.id
        dailyRoutine = plan
    }
}
