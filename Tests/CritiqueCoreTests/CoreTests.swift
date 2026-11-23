import XCTest
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
