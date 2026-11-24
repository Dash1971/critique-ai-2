import XCTest

final class TrackerUITests: XCTestCase {
    func testHomeRoutineReviewSchedulesOnlyAfterConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-fixture"]
        app.launch()
        let review = app.buttons["Review & schedule"].firstMatch
        for _ in 0..<4 { if review.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.navigationBars["Schedule habit"].waitForExistence(timeout: 5))
        let uniqueText = "AI plan " + String(UUID().uuidString.prefix(6))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(review.exists)
        review.tap()
        let name = app.textFields["home-routine-habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(uniqueText)
        let title = try XCTUnwrap(name.value as? String)
        XCTAssertTrue(title.contains(uniqueText))
        app.navigationBars.buttons["Add habit"].tap()
        XCTAssertTrue(app.staticTexts["Added to your habits"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Habits"].tap()
        let row = app.cells.containing(.staticText, identifier: title).firstMatch
        for _ in 0..<5 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(app.buttons[title + ", not completed"].exists)
        // Preserve this synthetic saved habit as evidence; never reset fixtures.
    }

    func testHomeHabitCompletionUpdatesProgressAndPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.staticTexts["home-greeting"].exists)
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "scheduled habits completed")).firstMatch.label
        let counts = summary.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(counts.count, 2)
        let done = counts[0], scheduled = counts[1] + 1

        let title = "Home habit " + String(UUID().uuidString.prefix(6))
        app.tabBars.buttons["Habits"].tap(); app.buttons["Create habit"].tap()
        app.textFields["Habit name"].tap(); app.textFields["Habit name"].typeText(title)
        app.navigationBars.buttons["Save"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(app.staticTexts["home-daily-progress"].label, (Double(done) / Double(scheduled)).formatted(.percent.precision(.fractionLength(0))))
        let overview = XCTAttachment(screenshot: app.screenshot()); overview.name = "Home top - synthetic saved data"; overview.lifetime = .keepAlways; add(overview)
        let button = app.buttons[title + ", not completed"]
        for _ in 0..<6 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
        XCTAssertTrue(app.buttons[title + ", completed"].exists)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertEqual(app.staticTexts["home-daily-progress"].label, (Double(done + 1) / Double(scheduled)).formatted(.percent.precision(.fractionLength(0))))
        app.terminate(); app.launch()
        let saved = app.buttons[title + ", completed"]
        for _ in 0..<6 { if saved.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(saved.exists)
        // Keep the added synthetic habit and its saved completion as evidence.
    }

    func testRoutineRenameAndConfirmedDeletionPreserveRecordedWorkout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-workout-workflow-fixture"]
        let suffix = String(UUID().uuidString.prefix(6))
        let original = "Routine " + suffix, edited = "Edited routine " + suffix
        let recorded = "Routine record " + suffix
        func openWorkouts() {
            app.tabBars.buttons["Activity"].tap(); app.buttons["Workouts and routines"].tap()
        }
        func routineCell(_ title: String) -> XCUIElement {
            app.cells.containing(.staticText, identifier: title).firstMatch
        }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 {
                if element.isHittable { break }
                // Start above the software keyboard, within the active form.
                let keyboard = app.keyboards.firstMatch
                let bottom = keyboard.exists ? keyboard.frame.minY : app.frame.maxY
                let start = min(0.75, (bottom - app.frame.minY - 45) / app.frame.height)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26)))
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        app.launch(); openWorkouts(); app.buttons["Create routine"].tap()
        app.textFields["Routine title"].tap(); app.textFields["Routine title"].typeText(original)
        reveal(app.buttons["Add exercise"]); app.buttons["Add exercise"].tap()
        reveal(app.textFields["Exercise name"])
        app.textFields["Exercise name"].tap(); app.textFields["Exercise name"].typeText("Fixture squat")
        replace(app.textFields["kg"], with: "12")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(routineCell(original).waitForExistence(timeout: 5))
        routineCell(original).buttons["Edit"].tap()
        replace(app.textFields["Routine title"], with: edited)
        app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launch(); openWorkouts()
        XCTAssertTrue(routineCell(edited).waitForExistence(timeout: 5))
        routineCell(edited).buttons["Record session"].tap()
        XCTAssertEqual(app.textFields["Workout title"].value as? String, edited)
        XCTAssertEqual(app.textFields["Exercise name"].value as? String, "Fixture squat")
        replace(app.textFields["Workout title"], with: recorded)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Workout editor before save"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        // Query the active modal's unique button without assuming its toolbar
        // is exposed as a navigation-bar descendant on every OS version.
        let saveWorkout = app.buttons["Save"]
        XCTAssertTrue(saveWorkout.waitForExistence(timeout: 5))
        XCTAssertTrue(saveWorkout.isHittable)
        saveWorkout.tap()
        XCTAssertTrue(app.textFields["Workout title"].waitForNonExistence(timeout: 5),
                      "A saved workout must dismiss its editor")
        routineCell(edited).buttons["Edit"].tap()
        reveal(app.buttons["Delete routine"]); app.buttons["Delete routine"].tap()
        // Compact confirmation dialogs may be popovers rather than sheets.
        let confirmation = app.staticTexts["Delete this routine? Saved workouts will remain."]
        let deletionHierarchy = XCTAttachment(string: app.debugDescription)
        deletionHierarchy.name = "Routine deletion confirmation"; deletionHierarchy.lifetime = .keepAlways; add(deletionHierarchy)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let outside = app.descendants(matching: .any).matching(identifier: "PopoverDismissRegion").firstMatch
        if outside.exists { outside.tap() }
        else { app.buttons["Cancel"].tap() }
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Routine"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(routineCell(edited).exists)
        routineCell(edited).buttons["Edit"].tap()
        reveal(app.buttons["Delete routine"]); app.buttons["Delete routine"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let deleteButtons = app.buttons.matching(identifier: "Delete routine").allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(deleteButtons.count, 1, "Only the active confirmation action may be tapped")
        try XCTUnwrap(deleteButtons.first).tap()
        app.terminate(); app.launch(); openWorkouts()
        XCTAssertFalse(routineCell(edited).exists)
        reveal(app.staticTexts[recorded])
        XCTAssertTrue(app.staticTexts[recorded].exists, "Deleting a template must preserve its recorded workout")
    }
    func testGoalDeadlinePickerCancellationAndRelaunchPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-goal-workflow-fixture"]
        let title = "Deadline workflow " + UUID().uuidString.prefix(6)
        func cell() -> XCUIElement { app.cells.containing(.staticText, identifier: String(title)).firstMatch }
        func openGoals() { app.tabBars.buttons["Goals"].tap() }
        app.launch(); openGoals(); app.buttons["Create goal"].tap()
        app.textFields["Goal title"].tap(); app.textFields["Goal title"].typeText(String(title))
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(cell().waitForExistence(timeout: 5))
        cell().buttons["Edit"].tap()
        let picker = app.buttons["Date Picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(picker.value as? String)
        func chooseDay(_ day: Int) {
            picker.tap()
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Native goal deadline calendar"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let defaultMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
            let month = DateFormatter(); month.locale = Locale(identifier: "en_US"); month.dateFormat = "MMMM"
            let labelPart = month.string(from: defaultMonth) + " " + String(day)
            let dated = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", labelPart)).firstMatch
            let numbered = app.buttons[String(day)]
            let target = dated.exists ? dated : numbered
            XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected a selectable day in the native deadline calendar")
            target.tap()
            let dismissRegion = app.buttons["PopoverDismissRegion"]
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
            dismissRegion.tap()
            let pickerReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [pickerReady], timeout: 5), .completed,
                           "Deadline value must be read only after the native calendar is dismissed")
        }
        chooseDay(15)
        let changed = try XCTUnwrap(picker.value as? String)
        XCTAssertNotEqual(changed, original)
        app.navigationBars.buttons["Cancel"].tap()
        cell().buttons["Edit"].tap()
        XCTAssertEqual(picker.value as? String, original, "Cancel must not persist a changed deadline")
        chooseDay(15)
        XCTAssertEqual(picker.value as? String, changed)
        app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launch(); openGoals()
        cell().buttons["Edit"].tap()
        XCTAssertEqual(picker.value as? String, changed, "Saved deadline must survive relaunch")
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testGoalEditCadenceHistoryAndConfirmedDeletionPersistWithoutReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-goal-workflow-fixture"]
        let original = "Goal workflow " + UUID().uuidString.prefix(6)
        let edited = original + " edited"
        func openGoals() { app.tabBars.buttons["Goals"].tap() }
        func cell(_ title: String) -> XCUIElement {
            app.cells.containing(.staticText, identifier: title).firstMatch
        }
        func beginDelete() {
            cell(String(edited)).swipeLeft(); app.buttons["Delete"].tap()
            XCTAssertTrue(app.buttons["Delete goal"].waitForExistence(timeout: 5))
        }
        app.launch(); openGoals()
        app.buttons["Create goal"].tap()
        app.textFields["Goal title"].tap(); app.textFields["Goal title"].typeText(String(original))
        replace(app.textFields["Target"], with: "0.5")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(cell(String(original)).waitForExistence(timeout: 5))
        cell(String(original)).buttons["Update progress"].tap()
        replace(app.textFields["Total"], with: "0.25")
        app.navigationBars.buttons["Save"].tap()
        cell(String(original)).buttons["Edit"].tap()
        replace(app.textFields["Goal title"], with: String(edited))
        replace(app.textFields["Category"], with: "Verification")
        app.buttons["Period, Monthly"].tap(); app.buttons["Weekly"].tap()
        app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launch(); openGoals()
        XCTAssertTrue(cell(String(edited)).waitForExistence(timeout: 5))
        XCTAssertTrue(cell(String(edited)).staticTexts["0.25 / 0.5 · Weekly"].exists)
        cell(String(edited)).buttons["Update progress"].tap()
        XCTAssertEqual(app.textFields["Total"].value as? String, "0.25")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "0.25")).firstMatch.exists)
        replace(app.textFields["Total"], with: "0.5")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(cell(String(edited)).images["Completed"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openGoals()
        XCTAssertTrue(cell(String(edited)).images["Completed"].waitForExistence(timeout: 5))
        beginDelete(); cancelRecovery(app.sheets.firstMatch, in: app)
        XCTAssertTrue(cell(String(edited)).exists)
        beginDelete(); app.buttons["Delete goal"].tap()
        XCTAssertTrue(cell(String(edited)).waitForNonExistence(timeout: 5))
        app.terminate(); app.launch(); openGoals()
        XCTAssertFalse(cell(String(edited)).exists)
    }

    func testHabitEditScheduleAndConfirmedDeletionPersistWithoutReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-habit-workflow-fixture"]
        let original = "Habit workflow " + UUID().uuidString.prefix(6)
        let edited = original + " edited"
        let today = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1]
        func openHabits() { app.tabBars.buttons["Habits"].tap() }
        func toggleToday() {
            let control = app.switches[today]
            for _ in 0..<3 { if control.exists && control.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            let previous = control.value as? String
            let before = XCTAttachment(string: app.debugDescription)
            before.name = "Habit schedule before toggle"; before.lifetime = .keepAlways; add(before)
            // SwiftUI exposes both the full-width labelled row and its inner
            // UISwitch. The row midpoint is not the switch hit target.
            let thumb = control.switches.firstMatch
            XCTAssertTrue(thumb.exists); thumb.tap()
            let after = XCTAttachment(string: app.debugDescription)
            after.name = "Habit schedule after toggle"; after.lifetime = .keepAlways; add(after)
            XCTAssertNotEqual(control.value as? String, previous, "The weekday control must change before saving")
        }
        func beginDelete() {
            app.cells.containing(.button, identifier: "Edit " + edited).firstMatch.swipeLeft()
            app.buttons["Delete"].tap()
            XCTAssertTrue(app.buttons["Delete habit"].waitForExistence(timeout: 5))
        }
        app.launch(); openHabits()
        app.buttons["Create habit"].tap()
        app.textFields["Habit name"].tap(); app.textFields["Habit name"].typeText(String(original))
        app.navigationBars.buttons["Save"].tap()
        app.buttons[String(original) + ", not completed"].tap()
        app.buttons["Edit " + original].tap()
        replace(app.textFields["Habit name"], with: String(edited))
        replace(app.textFields["Category"], with: "Verification")
        toggleToday(); app.navigationBars.buttons["Save"].tap()
        let completion = app.buttons[String(edited) + ", completed"]
        XCTAssertTrue(completion.waitForExistence(timeout: 5)); XCTAssertFalse(completion.isEnabled)
        app.terminate(); app.launch(); openHabits()
        XCTAssertTrue(completion.waitForExistence(timeout: 5)); XCTAssertFalse(completion.isEnabled)
        app.buttons["Edit " + edited].tap(); toggleToday()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(completion.isEnabled, "Re-enabling the schedule must preserve its saved completion")
        beginDelete(); cancelRecovery(app.sheets.firstMatch, in: app)
        XCTAssertTrue(app.buttons["Edit " + edited].exists)
        beginDelete(); app.buttons["Delete habit"].tap()
        XCTAssertTrue(app.buttons["Edit " + edited].waitForNonExistence(timeout: 5))
        app.terminate(); app.launch(); openHabits()
        XCTAssertFalse(app.buttons["Edit " + edited].exists)
        XCTAssertFalse(completion.exists)
    }
    // Use an isolated focus fixture and preserve its existing session history.
    func testFocusDeadlineBackgroundSettlementAndRelaunchAreExactlyOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-focus-lifecycle-fixture"]
        app.launch()
        func openFocus() {
            app.tabBars.buttons["Activity"].tap()
            app.buttons["Focus and timers"].tap()
        }
        func workRows() -> XCUIElementQuery {
            app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", "Work ·"))
        }
        openFocus()
        XCTAssertTrue(app.buttons["Start timer"].exists, "Do not replace an unfinished saved timer")
        let baseline = workRows().count
        replace(app.textFields["Minutes"], with: "0.2")
        app.buttons["Start timer"].tap()
        XCTAssertTrue(app.buttons["Cancel without saving"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let deadlineElapsed = expectation(description: "Saved timer deadline passes while backgrounded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { deadlineElapsed.fulfill() }
        wait(for: [deadlineElapsed], timeout: 20)
        app.activate()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 8))
        XCTAssertEqual(workRows().count, baseline + 1)
        app.terminate(); app.launch(); openFocus()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 5))
        XCTAssertEqual(workRows().count, baseline + 1, "Relaunch must not settle the same saved deadline twice")
        replace(app.textFields["Minutes"], with: "2")
        app.buttons["Start timer"].tap()
        app.buttons["Cancel without saving"].tap()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openFocus()
        XCTAssertEqual(workRows().count, baseline + 1, "Cancelling an incomplete timer must not create another session")
    }
    func testCoachCompletedPeriodEvidencePreviewUsesSavedComparisonWithoutInference() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-testing-comparison-fixture"]; app.launch()
        app.tabBars.buttons["Coach"].tap()
        app.segmentedControls.buttons["Completed periods"].tap()
        app.buttons["App-calculated evidence"].tap()
        let recent = app.staticTexts["coach-evidence-recent_period"]
        if !recent.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.label.contains("completions: 1 out of 7"))
        XCTAssertTrue(recent.label.contains("workouts: 1; workout minutes: 30"))
        XCTAssertTrue(recent.label.contains("work-focus minutes: 35"))
        let previous = app.staticTexts["coach-evidence-previous_period"]
        XCTAssertTrue(previous.exists)
        XCTAssertTrue(previous.label.contains("workout minutes: 45"))
        XCTAssertTrue(previous.label.contains("work-focus minutes: 25"))
        app.swipeDown(); app.swipeDown()
        app.segmentedControls.buttons["Snapshot"].tap()
        XCTAssertTrue(app.staticTexts["coach-evidence-comparison_limit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["coach-evidence-previous_period"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists, "Preview selection must not start inference")
    }
    // Prepare a new exclusive synthetic comparison fixture before this test.
    func testRecordedPeriodComparisonDisplaysNonzeroSavedTotals() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-testing-comparison-fixture"]; app.launch()
        let link = app.buttons["Compare recorded periods"]
        if !link.waitForExistence(timeout: 5) || !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        func verify(_ period: String, _ habits: String, _ workouts: String, _ minutes: String, _ focus: String) {
            for (metric, label, expected) in [("habits", "Habit completions saved", habits), ("workouts", "Workouts saved", workouts), ("workout-minutes", "Workout minutes saved", minutes), ("focus-minutes", "Work-focus minutes saved", focus)] {
                let value = app.staticTexts["comparison-\(period)-\(metric)"]
                XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.label, "\(label), \(expected)")
            }
        }
        verify("recent", "1 / 7 scheduled", "1", "30", "35")
        app.swipeUp()
        verify("previous", "1 / 7 scheduled", "1", "45", "25")
        app.swipeDown(); app.swipeDown()
        app.segmentedControls.buttons["14 days"].tap()
        verify("recent", "2 / 14 scheduled", "2", "75", "60")
        app.swipeUp()
        verify("previous", "1 / 14 scheduled", "1", "60", "0")
    }
    func testRecordedPeriodComparisonRefreshesStaleWindowOnForeground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-stale-comparison"]; app.launch()
        let link = app.buttons["Compare recorded periods"]
        if !link.waitForExistence(timeout: 5) || !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        let recent = app.staticTexts["comparison-recent-range"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        let calendar = Calendar.current
        func key(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        XCTAssertEqual(recent.label, "\(key(-8)) through \(key(-2))", "QA fixture must demonstrate a stale window before refresh")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.label, "\(key(-7)) through \(key(-1))", "Foreground must replace stale snapshot with the actual date")
        let recentImage = XCTAttachment(screenshot: app.screenshot())
        recentImage.name = "recorded-periods-foreground-recent"; recentImage.lifetime = .keepAlways; add(recentImage)
        app.swipeUp()
        let previous = app.staticTexts["comparison-previous-range"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertEqual(previous.label, "\(key(-14)) through \(key(-8))")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Missing records do not establish inactivity. These are saved totals, not a score of overall improvement."].waitForExistence(timeout: 5))
        let scopeImage = XCTAttachment(screenshot: app.screenshot())
        scopeImage.name = "recorded-periods-scope"; scopeImage.lifetime = .keepAlways; add(scopeImage)
    }
    func testRecordedPeriodComparisonSwitchesCompletedWindows() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let link = app.buttons["Compare recorded periods"]
        if !link.waitForExistence(timeout: 5) { app.swipeUp() }
        if !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.navigationBars["Recorded periods"].waitForExistence(timeout: 5))
        let calendar = Calendar.current; let cutoff = calendar.startOfDay(for: Date())
        func key(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        for days in [7, 14, 30] {
            app.segmentedControls.buttons["\(days) days"].tap()
            let start = calendar.date(byAdding: .day, value: -days, to: cutoff)!
            let end = calendar.date(byAdding: .day, value: -1, to: cutoff)!
            let recent = app.staticTexts["comparison-recent-range"]
            XCTAssertTrue(recent.waitForExistence(timeout: 5))
            XCTAssertEqual(recent.label, "\(key(start)) through \(key(end))")
        }
        XCTAssertTrue(app.staticTexts["Two completed periods; today is excluded."].exists)
        app.navigationBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Compare recorded periods"].waitForExistence(timeout: 5))
    }
    // Prepare a new exclusive --scenario backup-import fixture, never normal data.
    func testFailedLoadBackupImportRequiresConfirmationAndPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-backup-import-fixture"]
        app.launch()
        let failedLoad = app.staticTexts["Saved data could not be opened"]
        XCTAssertTrue(failedLoad.waitForExistence(timeout: 10))
        selectBackupFixture("Critique Valid Backup", in: app)
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        cancelRecovery(confirmation, in: app)
        XCTAssertTrue(failedLoad.exists, "Cancelling a valid backup must not replace unreadable data")
        app.terminate(); app.launch()
        XCTAssertTrue(failedLoad.waitForExistence(timeout: 10),
                      "Cancelled import must leave the original failed-load state across relaunch")
        selectBackupFixture("Critique Valid Backup", in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Replace current data"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, "Imported fixture")
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testBackupExportWritesNativeJSONDocument() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let nickname = "Export " + String(UUID().uuidString.prefix(6))
        app.buttons["Settings"].tap()
        replace(app.textFields["Username"], with: nickname)
        app.navigationBars.buttons["Save"].tap()
        app.buttons["Settings"].tap(); app.swipeUp()
        app.buttons["Export backup"].tap()
        XCTAssertTrue(app.searchFields["Search"].firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        capturePicker("export-destination", in: app)
        let folder = app.cells["CritiqueUITestBackups, Folder"]
        if folder.waitForExistence(timeout: 5) {
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        }
        let pickerBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(pickerBar.buttons["CritiqueUITestBackups, Actions Menu"].waitForExistence(timeout: 5), app.debugDescription)
        let export = pickerBar.buttons["Save"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), app.debugDescription)
        export.tap()
        XCTAssertTrue(export.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.alerts["Changes were not saved"].exists)
        print("BACKUP_EXPORT_EXPECTED_PROFILE|\(nickname)")
        app.terminate()
    }
    func testNewerSchemaBackupShowsUpdateErrorWithoutReplacingSavedData() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["Settings"].tap()
        let nickname = try XCTUnwrap(app.textFields["Username"].value as? String)
        app.swipeUp()
        selectBackupFixture("Critique Newer Schema Backup", in: app)
        let error = app.alerts["Changes were not saved"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(error.staticTexts["This backup was created by a newer app. Update before restoring."].exists)
        XCTAssertFalse(app.buttons["Replace current data"].exists,
                       "A newer-schema backup must never offer a replacement confirmation")
        error.buttons["OK"].tap(); app.swipeDown()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname)
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Unsupported-version rejection must preserve saved data across relaunch")
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testSemanticInvalidBackupShowsValidationErrorWithoutReplacingSavedData() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["Settings"].tap()
        let nickname = try XCTUnwrap(app.textFields["Username"].value as? String)
        app.swipeUp()
        selectBackupFixture("Critique Semantic Invalid Backup", in: app)
        let error = app.alerts["Changes were not saved"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(error.staticTexts["Enter valid timer and water targets."].exists)
        XCTAssertFalse(app.buttons["Replace current data"].exists,
                       "A semantically invalid backup must never offer a replacement confirmation")
        error.buttons["OK"].tap(); app.swipeDown()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname)
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Semantic validation rejection must preserve saved data across relaunch")
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testInvalidBackupShowsErrorWithoutReplacingSavedData() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let nickname = "Retain " + String(UUID().uuidString.prefix(6))
        app.buttons["Settings"].tap()
        replace(app.textFields["Username"], with: nickname)
        app.navigationBars.buttons["Save"].tap()
        app.buttons["Settings"].tap(); app.swipeUp()
        selectBackupFixture("Critique Invalid Backup", in: app)
        let error = app.alerts["Changes were not saved"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Replace current data"].exists,
                       "A malformed backup must not offer a replacement confirmation")
        error.buttons["OK"].tap()
        app.swipeDown()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname)
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Rejecting a malformed backup must leave the persisted profile unchanged")
        app.navigationBars.buttons["Cancel"].tap()
    }
    private func capturePicker(_ label: String, in app: XCUIApplication) {
        let hierarchy = app.debugDescription
        print("BACKUP_PICKER_\(label)\n\(hierarchy)\nEND_BACKUP_PICKER_\(label)")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "backup-picker-\(label)"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    // Prepare only synthetic Files fixtures with scripts/prepare_backup_ui_fixtures.py.
    func testValidBackupImportRequiresConfirmationAndPersistsAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let nickname = "Keep " + String(UUID().uuidString.prefix(6))
        app.buttons["Settings"].tap()
        replace(app.textFields["Username"], with: nickname)
        app.navigationBars.buttons["Save"].tap()
        app.buttons["Settings"].tap(); app.swipeUp()
        selectBackupFixture("Critique Valid Backup", in: app)
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        cancelRecovery(confirmation, in: app)
        app.swipeDown()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Selecting a valid backup must not replace data before confirmation")
        app.swipeUp(); selectBackupFixture("Critique Valid Backup", in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Replace current data"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, "Imported fixture")
        app.navigationBars.buttons["Cancel"].tap()
    }
    private func selectBackupFixture(_ name: String, in app: XCUIApplication) {
        app.buttons["Restore backup"].tap()
        // Settings also has Cancel. Wait for a picker-owned control before
        // querying its asynchronously attached accessibility subtree.
        XCTAssertTrue(app.searchFields["Search"].firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if !file.waitForExistence(timeout: 3) {
            let folder = app.cells["CritiqueUITestBackups, Folder"]
            if !folder.waitForExistence(timeout: 15) {
                let browse = app.buttons["Browse"].firstMatch
                if browse.exists { browse.tap() }
                let local = app.staticTexts["On My iPhone"].firstMatch
                XCTAssertTrue(local.waitForExistence(timeout: 5), app.debugDescription); local.tap()
            }
            XCTAssertTrue(folder.waitForExistence(timeout: 5))
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        }
        XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
    func testBackupExportCancellationPreservesSavedProfile() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let nickname = "Backup " + String(UUID().uuidString.prefix(6))
        app.buttons["Settings"].tap()
        replace(app.textFields["Username"], with: nickname)
        app.navigationBars.buttons["Save"].tap()
        app.buttons["Settings"].tap(); app.swipeUp()
        app.buttons["Export backup"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(app.buttons["Export backup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Changes were not saved"].exists,
                       "Cancelling an export is not a failed data write")
        app.navigationBars.buttons["Cancel"].tap()
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, nickname,
                       "Cancelling an export must preserve saved data across relaunch")
        app.navigationBars.buttons["Cancel"].tap()
    }
    // Prepare only the disposable fixture with scripts/prepare_recovery_ui_fixture.py.
    func testFailedLoadRecoveryPreservesDataUntilConfirmed() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-recovery-fixture"]
        app.launch()
        let failedLoad = app.staticTexts["Saved data could not be opened"]
        XCTAssertTrue(failedLoad.waitForExistence(timeout: 10))
        app.buttons["Try again"].tap()
        XCTAssertTrue(failedLoad.exists, "Retry must not reset unreadable data")
        app.buttons["Restore backup"].tap()
        let pickerCancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 15))
        pickerCancel.tap()
        XCTAssertTrue(failedLoad.exists, "Cancelling the file picker must not replace data")
        app.buttons["Restore previous save"].tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        cancelRecovery(confirmation, in: app)
        XCTAssertTrue(failedLoad.exists, "Cancelling recovery must leave failed data untouched")
        app.buttons["Restore previous save"].tap()
        confirmation.buttons["Restore previous save"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, "Recovered fixture")
        app.swipeUp()
        XCTAssertFalse(app.buttons["Restore previous save"].isEnabled,
                       "The replaced unreadable payload must not become a valid restore candidate")
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testPreviousSaveRecoveryConfirmsAndPersistsAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let before = "Before " + String(UUID().uuidString.prefix(6))
        let after = "After " + String(UUID().uuidString.prefix(6))
        for nickname in [before, after] {
            app.buttons["Settings"].tap()
            replace(app.textFields["Username"], with: nickname)
            app.navigationBars.buttons["Save"].tap()
        }
        app.buttons["Settings"].tap(); app.swipeUp()
        app.buttons["Restore previous save"].tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        cancelRecovery(confirmation, in: app)
        app.swipeDown()
        XCTAssertEqual(app.textFields["Username"].value as? String, after,
                       "Cancelling recovery must not change saved records")
        app.swipeUp(); app.buttons["Restore previous save"].tap()
        confirmation.buttons["Restore previous save"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["Username"].value as? String, before)
        app.navigationBars.buttons["Cancel"].tap()
    }
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
    private func cancelRecovery(_ confirmation: XCUIElement, in app: XCUIApplication) {
        if confirmation.buttons["Cancel"].exists {
            confirmation.buttons["Cancel"].tap()
        } else {
            // Compact popovers expose an outside-dismiss region, not Cancel.
            app.otherElements["PopoverDismissRegion"].tap()
        }
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
    }
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
}
