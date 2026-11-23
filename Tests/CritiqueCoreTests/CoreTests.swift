import XCTest
import CSQLite
@testable import CritiqueCore

final class CoreTests: XCTestCase {
    func databaseURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("state.sqlite")
    }
    func testSavedDataSurvivesClosingAndReopeningDatabase() throws {
        let url = try databaseURL()
        var database: Database? = try Database(url: url)
        var state = AppState(); state.habits.append(Habit(title: "Read"))
        try database!.save(state); database = nil
        let reopened = try Database(url: url)
        let restored = try reopened.load()
        XCTAssertEqual(restored.habits.first?.title, "Read")
        XCTAssertEqual(restored.habits.first?.id, state.habits.first?.id)
    }
    func testInvalidSaveLeavesLastCommittedStateIntact() throws {
        let database = try Database(url: databaseURL())
        var state = AppState(); state.habits.append(Habit(title: "Read")); try database.save(state)
        state.habits[0].title = "   "
        XCTAssertThrowsError(try database.save(state))
        XCTAssertEqual(try database.load().habits[0].title, "Read")
    }
    func testBackupRejectsUnknownSchemaWithoutChangingLiveData() throws {
        let database = try Database(url: databaseURL())
        var state = AppState(); state.profile.username = "Tester"; try database.save(state)
        var exported = try JSONSerialization.jsonObject(with: Database.encode(state)) as! [String: Any]
        exported["schema"] = 99
        XCTAssertThrowsError(try Database.decode(JSONSerialization.data(withJSONObject: exported)))
        XCTAssertEqual(try database.load().profile.username, "Tester")
    }
    func testDuplicateIdentifiersRejectedOnImport() throws {
        var state = AppState(); let habit = Habit(title: "Read"); state.habits = [habit, habit]
        XCTAssertThrowsError(try Database.decode(Database.encode(state)))
    }
    // These tests mutate only disposable synthetic databases.
    private func execute(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw DataError.database(String(cString: sqlite3_errmsg(handle)))
        }
    }
    func testRecoveryRequiresAPreviousSave() throws {
        let database = try Database(url: databaseURL())
        XCTAssertNil(try database.recoverySnapshot())
        XCTAssertThrowsError(try database.restoreRecoverySnapshot())
        var first = AppState(); first.profile.username = "First"; try database.save(first)
        XCTAssertNil(try database.recoverySnapshot())
        XCTAssertThrowsError(try database.restoreRecoverySnapshot())
        XCTAssertEqual(try database.load().profile.username, "First")
    }
    func testRecoveryRestoresPreviousSaveAndCanUndoAcrossReopen() throws {
        let url = try databaseURL()
        var database: Database? = try Database(url: url)
        var state = AppState(); state.profile.username = "Before"; try database!.save(state)
        state.profile.username = "After"; try database!.save(state)
        XCTAssertEqual(try database!.restoreRecoverySnapshot().profile.username, "Before")
        database = nil
        let reopened = try Database(url: url)
        XCTAssertEqual(try reopened.load().profile.username, "Before")
        XCTAssertEqual(try reopened.recoverySnapshot()?.profile.username, "After")
        XCTAssertEqual(try reopened.restoreRecoverySnapshot().profile.username, "After")
    }
    func testRecoveryRepairsInvalidCurrentPayloadWithoutInstallingInvalidSnapshot() throws {
        let url = try databaseURL(); let database = try Database(url: url)
        var state = AppState(); state.profile.username = "Recoverable"; try database.save(state)
        state.profile.username = "Second"; try database.save(state)
        try execute("UPDATE app_state SET payload='broken-json' WHERE id=1", at: url)
        XCTAssertThrowsError(try database.load())
        XCTAssertEqual(try database.restoreRecoverySnapshot().profile.username, "Recoverable")
        // The original invalid row remains as recovery until a successful save.
        XCTAssertThrowsError(try database.recoverySnapshot())
        XCTAssertThrowsError(try database.restoreRecoverySnapshot())
        XCTAssertEqual(try database.load().profile.username, "Recoverable")
    }
    func testInvalidOrFutureRecoveryLeavesCurrentRecordsIntact() throws {
        let url = try databaseURL(); let database = try Database(url: url)
        var state = AppState(); state.profile.username = "Keep me"; try database.save(state)
        for payload in ["broken-json", "{\"schema\":99}"] {
            try execute("INSERT OR REPLACE INTO recovery(id,payload) VALUES(1,'\(payload)')", at: url)
            XCTAssertThrowsError(try database.restoreRecoverySnapshot())
            XCTAssertEqual(try database.load().profile.username, "Keep me")
        }
        var future = try JSONSerialization.jsonObject(with: Database.encode(state)) as! [String: Any]
        future["schema"] = 99
        let json = String(decoding: try JSONSerialization.data(withJSONObject: future), as: UTF8.self)
            .replacingOccurrences(of: "'", with: "''")
        try execute("UPDATE recovery SET payload='\(json)' WHERE id=1", at: url)
        XCTAssertThrowsError(try database.restoreRecoverySnapshot()) { error in
            guard case DataError.unsupportedVersion = error else { return XCTFail("Expected unsupported schema, got \(error)") }
        }
        XCTAssertEqual(try database.load().profile.username, "Keep me")
    }
    func testFailedRecoveryWriteRollsBackBothRows() throws {
        let url = try databaseURL(); let database = try Database(url: url)
        var state = AppState(); state.profile.username = "Before"; try database.save(state)
        state.profile.username = "After"; try database.save(state)
        try execute("CREATE TRIGGER fail_update BEFORE UPDATE ON app_state BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END", at: url)
        XCTAssertThrowsError(try database.restoreRecoverySnapshot())
        XCTAssertEqual(try database.load().profile.username, "After")
        XCTAssertEqual(try database.recoverySnapshot()?.profile.username, "Before")
    }
    func testTimerSettlesExactlyOnceAtItsDeadline() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = AppState(); state.timer = RunningTimer(minutes: 25, kind: "Work", now: start)
        state.settleTimer(now: start.addingTimeInterval(3600)); state.settleTimer(now: start.addingTimeInterval(7200))
        XCTAssertNil(state.timer); XCTAssertEqual(state.focus.count, 1)
        XCTAssertEqual(state.focus[0].seconds, 1500)
    }
    func testCancelledIncompleteTimerDoesNotInventFocusActivity() {
        let start = Date()
        var state = AppState(); state.timer = RunningTimer(minutes: 25, kind: "Work", now: start)
        state.settleTimer(now: start.addingTimeInterval(5), cancel: true)
        XCTAssertTrue(state.focus.isEmpty); XCTAssertNil(state.timer); XCTAssertEqual(state.xp, 0)
    }
    func testNutritionAndFocusStatisticsUseRecordedValues() {
        let date = Date(); var state = AppState()
        var meal = Meal(); meal.date = date; meal.food = Food(name: "Custom meal")
        meal.food.calories = 100; meal.food.protein = 10; meal.servings = 2
        state.meals.append(meal)
        state.focus.append(FocusSession(started: date, ended: date.addingTimeInterval(600)))
        let stats = state.stats(on: date)
        XCTAssertEqual(stats.calories, 200); XCTAssertEqual(stats.protein, 20); XCTAssertEqual(stats.focusMinutes, 10)
    }
    func testCoachContextExcludesPhotoAndProfileIdentity() throws {
        var state = AppState(); state.profile.username = "PrivateTestName"; state.profile.photo = Data([1,2,3])
        state.habits.append(Habit(title: "Read"))
        let object = try JSONSerialization.jsonObject(with: state.coachContext()) as! [String: Any]
        XCTAssertNil(object["profile"]); XCTAssertNil(object["photo"]); XCTAssertNil(object["username"])
        XCTAssertEqual((object["habits"] as? [[String: Any]])?.count, 1)
    }
}
