import Foundation

public struct DailyStats: Identifiable, Equatable {
    public var id: String { day }
    public let day: String
    public let dueHabits: Int
    public let doneHabits: Int
    public let workouts: Int
    public let completedGoals: Int
    public let focusMinutes: Double
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let water: Int
    public var completion: Double { dueHabits == 0 ? 0 : Double(doneHabits) / Double(dueHabits) }
    public var activities: Int { doneHabits + workouts + completedGoals + (focusMinutes > 0 ? 1 : 0) }
}

public extension AppState {
    func stats(on date: Date, calendar: Calendar = .current) -> DailyStats {
        let key = Day.key(date, calendar: calendar)
        func same(_ date: Date) -> Bool { Day.key(date, calendar: calendar) == key }
        let due = habits.filter { $0.scheduled(on: date, calendar: calendar) }
        let meals = meals.filter { same($0.date) }
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let focusMinutes = focus.filter { $0.kind == "Work" }.reduce(0.0) { total, session in
            total + max(0, min(session.ended, dayEnd).timeIntervalSince(max(session.started, dayStart))) / 60
        }
        return DailyStats(day: key, dueHabits: due.count,
            doneHabits: due.filter { $0.completed.contains(key) }.count,
            workouts: workouts.filter { same($0.date) }.count,
            completedGoals: goals.filter { $0.completedDate.map(same) ?? false }.count,
            focusMinutes: focusMinutes,
            calories: meals.reduce(0) { $0 + $1.food.calories * $1.servings },
            protein: meals.reduce(0) { $0 + $1.food.protein * $1.servings },
            carbs: meals.reduce(0) { $0 + $1.food.carbs * $1.servings },
            fat: meals.reduce(0) { $0 + $1.food.fat * $1.servings },
            water: water.filter { same($0.date) }.reduce(0) { $0 + $1.milliliters })
    }
    var xp: Int {
        habits.reduce(0) { $0 + $1.completed.count * 10 } + workouts.count * 50
        + goals.filter(\.completed).count * 100
        + focus.filter { $0.kind == "Work" }.reduce(0) { $0 + Int($1.seconds / 60) }
    }
    var level: Int { xp / 250 + 1 }
    var achievements: [String] {
        var badges: [String] = []
        if habits.contains(where: { !$0.completed.isEmpty }) { badges.append("First step") }
        if habits.contains(where: { $0.streak() >= 7 }) { badges.append("Seven-day consistency") }
        if workouts.count >= 1 { badges.append("First workout") }
        if workouts.count >= 10 { badges.append("Ten workouts") }
        if goals.contains(where: \.completed) { badges.append("Goal getter") }
        if focus.filter({ $0.kind == "Work" }).reduce(0, { $0 + $1.seconds }) >= 3600 { badges.append("Deep work hour") }
        if xp >= 1000 { badges.append("1,000 XP") }
        return badges
    }
    func series(days: Int, until now: Date = Date(), calendar: Calendar = .current) -> [DailyStats] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map { stats(on: $0, calendar: calendar) }
        }
    }
    func personalRecord(for name: String) -> Double {
        workouts.flatMap(\.exercises).filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.weight).max() ?? 0
    }
    mutating func toggleHabit(_ id: UUID, on date: Date) throws {
        guard let i = habits.firstIndex(where: { $0.id == id }), habits[i].scheduled(on: date), date <= Date() else { throw DataError.invalid("This habit is not scheduled for that date.") }
        let key = Day.key(date)
        if habits[i].completed.contains(key) { habits[i].completed.remove(key) } else { habits[i].completed.insert(key) }
    }
    mutating func settleTimer(now: Date = Date(), cancel: Bool = false) {
        guard let running = timer else { return }
        if now >= running.deadline {
            focus.append(FocusSession(started: running.started, ended: running.deadline, kind: running.kind))
            timer = nil
        } else if cancel { timer = nil }
    }
    /// User approves sending this actual data snapshot. Photo and account secrets
    /// are never part of it; it contains no fabricated metrics.
    func coachContext(now: Date = Date()) throws -> Data {
        struct Context: Encodable {
            var generatedAt: Date; var timezone: String; var habits: [Habit]; var workouts: [Workout]
            var goals: [Goal]; var meals: [Meal]; var water: [Water]; var focus: [FocusSession]
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Context(generatedAt: now, timezone: TimeZone.current.identifier,
            habits: habits, workouts: workouts, goals: goals, meals: meals, water: water, focus: focus))
    }
}
