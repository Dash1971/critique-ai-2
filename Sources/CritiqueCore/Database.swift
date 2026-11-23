import Foundation
import CSQLite

public enum DataError: Error, LocalizedError {
    case database(String), invalid(String), unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .database(let text), .invalid(let text): return text
        case .unsupportedVersion: return "This backup was created by a newer app. Update before restoring."
        }
    }
}

/// One independent SQLite database per app installation. Each whole-state commit is
/// atomic; failures leave the last committed state intact. Exports have a version.
public final class Database {
    private var handle: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw DataError.database(message)
        }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS recovery (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);")
    }
    deinit { if let handle { sqlite3_close(handle) } }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw DataError.database(String(cString: sqlite3_errmsg(handle)))
        }
    }
    public func load() throws -> AppState {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM app_state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw DataError.database("Cannot read saved data") }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return AppState() }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw DataError.database("Cannot read saved data") }
        return try Self.decode(Data(String(cString: bytes).utf8))
    }
    public func save(_ state: AppState) throws {
        try Validation.check(state)
        let data = try Self.encode(state)
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM recovery; INSERT INTO recovery(id,payload) SELECT id,payload FROM app_state;")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT INTO app_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw DataError.database("Cannot prepare save") }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let payload = String(decoding: data, as: UTF8.self)
            guard sqlite3_bind_text(statement, 1, payload, -1, transient) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else { throw DataError.database("Cannot save changes") }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public static func encode(_ state: AppState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }
    public static func decode(_ data: Data) throws -> AppState {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(AppState.self, from: data)
        guard state.schema == 1 else { throw DataError.unsupportedVersion }
        try Validation.check(state)
        return state
    }
}

public enum Validation {
    private static func title(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 200 else { throw DataError.invalid("Enter a name between 1 and 200 characters.") }
    }
    private static func number(_ value: Double, upper: Double = 1e9) throws {
        guard value.isFinite, value >= 0, value <= upper else { throw DataError.invalid("Enter a finite, nonnegative value.") }
    }
    private static func unique<T: Identifiable>(_ rows: [T]) throws where T.ID: Hashable {
        guard Set(rows.map(\.id)).count == rows.count else { throw DataError.invalid("Duplicate record identifiers in data.") }
    }
    private static func exercise(_ e: Exercise) throws {
        try title(e.name); try number(e.weight); try number(e.minutes)
        guard (1...10000).contains(e.sets), (1...100000).contains(e.reps) else { throw DataError.invalid("Sets and repetitions must be positive.") }
    }
    private static func food(_ food: Food) throws {
        try title(food.name)
        for n in [food.calories, food.protein, food.carbs, food.fat] { try number(n) }
    }
    public static func check(_ state: AppState) throws {
        guard state.schema == 1 else { throw DataError.unsupportedVersion }
        try title(state.profile.username)
        guard (state.profile.photo?.count ?? 0) <= 5_000_000 else { throw DataError.invalid("Choose a profile image smaller than 5 MB.") }
        try unique(state.habits); try unique(state.routines); try unique(state.workouts); try unique(state.foods)
        try unique(state.meals); try unique(state.water); try unique(state.goals); try unique(state.focus); try unique(state.screenTime); try unique(state.coach)
        for habit in state.habits {
            try title(habit.title)
            guard !habit.weekdays.isEmpty, habit.weekdays.isSubset(of: Set(1...7)), habit.reminderMinute.map({ (0..<1440).contains($0) }) ?? true else { throw DataError.invalid("Select a valid schedule and reminder time.") }
            guard habit.completed.allSatisfy({ Day.date($0) != nil }) else { throw DataError.invalid("Invalid completion date.") }
        }
        for routine in state.routines {
            try title(routine.title); try unique(routine.exercises)
            guard !routine.weekdays.isEmpty, routine.weekdays.isSubset(of: Set(1...7)),
                  routine.reminderMinute.map({ (0..<1440).contains($0) }) ?? true else { throw DataError.invalid("Select valid training days and reminder time.") }
            for e in routine.exercises { try exercise(e) }
        }
        for workout in state.workouts {
            try title(workout.title); try number(workout.minutes, upper: 1440); try unique(workout.exercises)
            for e in workout.exercises { try exercise(e) }
        }
        for f in state.foods { try food(f) }
        for meal in state.meals { try food(meal.food); try number(meal.servings); guard meal.servings > 0 else { throw DataError.invalid("Servings must be greater than zero.") } }
        for goal in state.goals {
            try title(goal.title); try number(goal.target); try unique(goal.updates)
            guard goal.target > 0 else { throw DataError.invalid("Goal target must be greater than zero.") }
            for u in goal.updates { try number(u.value) }
        }
        for water in state.water { guard (1...100000).contains(water.milliliters) else { throw DataError.invalid("Enter a positive water amount.") } }
        for focus in state.focus {
            guard focus.ended >= focus.started, focus.seconds <= 86400 else { throw DataError.invalid("Invalid focus duration.") }
        }
        for screen in state.screenTime { guard (0...1440).contains(screen.minutes) else { throw DataError.invalid("Screen time must be 0–1440 minutes per entry.") } }
        if let timer = state.timer { guard timer.deadline > timer.started, timer.deadline.timeIntervalSince(timer.started) <= 86400 else { throw DataError.invalid("Timer must be between 1 second and 24 hours.") } }
        try number(state.settings.focusMinutes, upper: 1440); try number(state.settings.breakMinutes, upper: 1440)
        guard state.settings.focusMinutes > 0, state.settings.breakMinutes > 0, (1...100000).contains(state.settings.waterTarget) else { throw DataError.invalid("Enter valid timer and water targets.") }
        guard (0..<1440).contains(state.settings.summaryMinute), state.settings.notifications.isSubset(of: Set(ReminderKind.allCases.map(\.rawValue))) else { throw DataError.invalid("Select valid notification settings.") }
    }
}
