import XCTest

final class TrackerUITests: XCTestCase {
    func testProfileDraftSurvivesSettingsNavigationAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["Settings"].tap()
        let nickname = "Reader " + String(UUID().uuidString.prefix(6))
        replace(app.textFields["Username"], with: nickname)
        app.buttons["AI configuration"].tap()
        XCTAssertTrue(app.navigationBars["AI configuration"].waitForExistence(timeout: 10))
        app.navigationBars["AI configuration"].buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Navigating to a settings detail must not discard an unsaved profile draft")
        app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname)
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testInvalidHabitShowsErrorWithoutClosingItsEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["Habits"].tap(); app.buttons["Create habit"].tap()
        XCTAssertTrue(app.textFields["Habit name"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Save"].tap()
        let alert = app.alerts["Changes were not saved"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Enter a name between 1 and 200 characters."].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.textFields["Habit name"].exists)
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testGoalAndWorkoutAppearInHistoryAndCalendar() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let suffix = String(UUID().uuidString.prefix(6))
        let goal = "Book " + suffix
        app.tabBars.buttons["Goals"].tap(); app.buttons["Create goal"].tap()
        app.textFields["Goal title"].tap(); app.textFields["Goal title"].typeText(goal)
        app.navigationBars.buttons["Save"].tap()
        let goalCell = app.cells.containing(.staticText, identifier: goal).firstMatch
        XCTAssertTrue(goalCell.waitForExistence(timeout: 10))
        goalCell.buttons["Update progress"].tap()
        replace(app.textFields["Total"], with: "1")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(goalCell.images["Completed"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Activity"].tap(); app.buttons["Workouts and routines"].tap()
        app.buttons["Record workout"].tap()
        let workout = "Session " + suffix
        app.textFields["Workout title"].tap(); app.textFields["Workout title"].typeText(workout)
        app.buttons["Add exercise"].tap()
        app.textFields["Exercise name"].tap(); app.textFields["Exercise name"].typeText("Squat")
        replace(app.textFields["kg"], with: "10")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[workout].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        app.tabBars.buttons["Activity"].tap(); app.buttons["Workouts and routines"].tap()
        XCTAssertTrue(app.staticTexts[workout].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Activity calendar"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts[goal].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", workout)).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Saved goal and workout calendar"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testSavedHabitMealAndTimerAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let name = "Read " + UUID().uuidString.prefix(6)
        app.tabBars.buttons["Habits"].tap()
        app.buttons["Create habit"].tap()
        let habitName = app.textFields["Habit name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 10))
        habitName.tap(); habitName.typeText(String(name))
        app.navigationBars.buttons["Save"].tap()
        let incomplete = app.buttons[String(name) + ", not completed"]
        XCTAssertTrue(incomplete.waitForExistence(timeout: 5)); incomplete.tap()
        XCTAssertTrue(app.buttons[String(name) + ", completed"].exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Habits"].tap()
        XCTAssertTrue(app.buttons[String(name) + ", completed"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Activity"].tap()
        app.buttons["Nutrition and water"].tap()
        app.buttons["Record meal"].tap()
        app.textFields["Food name"].tap(); app.textFields["Food name"].typeText("Oats " + String(name))
        replace(app.textFields["Calories per serving"], with: "150")
        replace(app.textFields["Servings"], with: "2")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Oats " + String(name)].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Activity"].tap(); app.buttons["Nutrition and water"].tap()
        XCTAssertTrue(app.staticTexts["Oats " + String(name)].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Focus and timers"].tap()
        replace(app.textFields["Minutes"], with: "0.1")
        app.buttons["Start timer"].tap()
        XCTAssertTrue(app.buttons["Cancel without saving"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Activity"].tap(); app.buttons["Focus and timers"].tap()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Work ·")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Persisted focus session on iPhone 13 simulator"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
}
