import Foundation

public enum Day {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        guard key.count == 10 else { return nil }
        let n = key.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3, let date = calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2])),
              Self.key(date, calendar: calendar) == key else { return nil }
        return date
    }
}

public struct Habit: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title = ""
    public var category = "Routine"
    public var weekdays = Set(1...7)
    public var created = Date()
    public var completed: Set<String> = []
    public var reminderMinute: Int? = nil
    public init(title: String = "") { self.title = title }
    public func scheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: created)
        && weekdays.contains(calendar.component(.weekday, from: date))
    }
    public func streak(at now: Date = Date(), calendar: Calendar = .current) -> Int {
        var cursor = calendar.startOfDay(for: now)
        var count = 0
        for offset in 0..<36600 {
            guard cursor >= calendar.startOfDay(for: created) else { break }
            if scheduled(on: cursor, calendar: calendar) {
                if completed.contains(Day.key(cursor, calendar: calendar)) { count += 1 }
                else if offset != 0 { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

public struct Exercise: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = ""
    public var kind = "Weight training"
    public var muscle = "Full body"
    public var sets = 3
    public var reps = 10
    public var weight = 0.0
    public var minutes = 0.0
    public init(name: String = "") { self.name = name }
}
public struct Routine: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title = ""
    public var exercises: [Exercise] = []
    public var weekdays = Set(1...7)
    public var reminderMinute: Int? = nil
    public init(title: String = "") { self.title = title }
}
public struct Workout: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title = ""
    public var date = Date()
    public var minutes = 30.0
    public var exercises: [Exercise] = []
    public var notes = ""
    public init(title: String = "") { self.title = title }
    public var volume: Double { exercises.reduce(0) { $0 + Double($1.sets * $1.reps) * $1.weight } }
}
public struct Food: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = ""
    public var category = "Other"
    public var calories = 0.0
    public var protein = 0.0
    public var carbs = 0.0
    public var fat = 0.0
    public init(name: String = "") { self.name = name }
}
public struct Meal: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var category = "Breakfast"
    public var food = Food()
    public var servings = 1.0
    public init() {}
}
public struct Water: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var milliliters = 250
    public init(milliliters: Int = 250) { self.milliliters = milliliters }
}
public struct Goal: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title = ""
    public var detail = ""
    public var category = "Personal"
    public var cadence = "Monthly"
    public var created = Date()
    public var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    public var target = 1.0
    public var updates: [GoalUpdate] = []
    public init(title: String = "") { self.title = title }
    public var progress: Double { updates.max(by: { $0.date < $1.date })?.value ?? 0 }
    public var fraction: Double { min(1, max(0, progress / max(1, target))) }
    public var completed: Bool { progress >= target }
    public var completedDate: Date? {
        guard completed else { return nil }
        var crossing: Date?
        for update in updates.sorted(by: { $0.date < $1.date }) {
            if update.value < target { crossing = nil }
            else if crossing == nil { crossing = update.date }
        }
        return crossing
    }
}
public struct GoalUpdate: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var value: Double
    public init(value: Double) { self.value = value }
}
public struct FocusSession: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var started: Date
    public var ended: Date
    public var kind: String
    public init(started: Date, ended: Date, kind: String = "Work") {
        self.started = started; self.ended = ended; self.kind = kind
    }
    public var seconds: Double { max(0, ended.timeIntervalSince(started)) }
}
public struct RunningTimer: Codable, Equatable {
    public var started: Date
    public var deadline: Date
    public var kind: String
    public init(minutes: Double, kind: String, now: Date = Date()) {
        started = now; deadline = now.addingTimeInterval(minutes * 60); self.kind = kind
    }
}
public struct ScreenTimeEntry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var minutes = 0
    public var note = ""
    public let source = "Manual"
    public init(minutes: Int = 0) { self.minutes = minutes }
}
public struct CoachMessage: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct Profile: Codable, Equatable {
    public var username = "You"
    public var photo: Data? = nil
    public var isPrivate = true
    public init() {}
}
public struct Settings: Codable, Equatable {
    public var theme = "Dark"
    public var notifications: Set<String> = []
    public var summaryMinute = 20 * 60
    public var waterTarget = 2000
    public var focusMinutes = 25.0
    public var breakMinutes = 5.0
    public var backendURL = ""
    public var coachConsent = false
    public init() {}
}
public struct AppState: Codable, Equatable {
    public var schema = 1
    public var profile = Profile()
    public var settings = Settings()
    public var habits: [Habit] = []
    public var routines: [Routine] = []
    public var workouts: [Workout] = []
    public var foods: [Food] = []
    public var meals: [Meal] = []
    public var water: [Water] = []
    public var goals: [Goal] = []
    public var focus: [FocusSession] = []
    public var timer: RunningTimer? = nil
    public var screenTime: [ScreenTimeEntry] = []
    public var coach: [CoachMessage] = []
    public init() {}
}
