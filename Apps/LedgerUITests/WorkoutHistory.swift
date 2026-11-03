import XCTest

/// F13 S1 and S2, criteria 1, 3, 5 and 6, on screen: the History tab in the running app. A sample workout with one set
/// is saved, then History lists it under its week as one button, the workout's name with its meta as its value; a tap
/// pushes its detail on History's stack, whose row opens the exercise's history over it, and back returns to the
/// detail, then to the list. Deleting it, from History or from a detail pushed on Today, empties the list and
/// Today's RECENT (risk R4: a deleted workout never comes back on Today); a detail covered while its workout is
/// deleted elsewhere pops when the lifter comes back to it (F13-S2-6). Nightly only: the `PR` plan selects
/// `Smoke`.
final class WorkoutHistory: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_savedWorkout_isListed_andOpensItsDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        app.tabBars.buttons["History"].tap()
        let title = app.staticTexts["history.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "History")
        XCTAssertTrue(app.buttons["Go to Today"].exists, "no workout yet")
        app.buttons["Go to Today"].tap()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        saveASampleWorkout(app)
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' minute' AND value CONTAINS ' pounds'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved workout is a row")
        XCTAssertFalse(app.buttons["Go to Today"].exists)
        attachScreenshot(of: app, named: "History, one workout")
        row.tap()
        let detail = app.staticTexts["history.workout.title"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "its detail is pushed")
        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Prescribed '")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5), "the receipt's row is a button")
        exercise.tap()
        XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 5), "the exercise's history")
        XCTAssertTrue(app.tabBars.buttons["History"].isSelected, "on History's stack")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "back to the detail")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists, "the list is as it was left")
    }

    /// Criterion 5: "Delete workout" asks first; confirmed, the detail closes and the list loses the row.
    @MainActor
    func test_deleteFromHistory_emptiesTheList() {
        let app = launchWithASavedWorkout()
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        deleteTheWorkout(in: app)
        XCTAssertTrue(app.buttons["Go to Today"].waitForExistence(timeout: 10), "the list lost its one row")
        XCTAssertFalse(row.exists)
    }

    /// Risk R4: a workout deleted from its detail pushed on Today (from "View session") does not come back there.
    @MainActor
    func test_deleteFromToday_leavesNoRecentRow() {
        let app = launchWithASavedWorkout()
        let recentRow = app.buttons.matching(NSPredicate(format: "label CONTAINS ' lb'")).firstMatch
        let viewSession = app.buttons["View session"]
        XCTAssertTrue(viewSession.waitForExistence(timeout: 10), "Today shows the session as logged")
        viewSession.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected, "the detail is on Today's stack")
        deleteTheWorkout(in: app)
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "back on Today")
        let noSessions = app.staticTexts["No sessions yet. Your first workout lands here."]
        XCTAssertTrue(noSessions.waitForExistence(timeout: 10), "RECENT has no row")
        XCTAssertFalse(recentRow.exists)
        XCTAssertFalse(viewSession.exists, "the deleted session is not shown as logged")
        attachScreenshot(of: app, named: "Today after a delete")
    }

    /// F13-S2-6: a detail covered by its row's exercise history, whose workout is deleted elsewhere (its detail on
    /// Today), pops when the lifter comes back to it: its task runs again, finds the workout gone and closes it.
    @MainActor
    func test_coveredDetail_deletedElsewhere_popsOnReturn() {
        let app = launchWithASavedWorkout()
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5))
        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Prescribed '")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
        let exerciseTitle = app.staticTexts["library.history.title"]
        XCTAssertTrue(exerciseTitle.waitForExistence(timeout: 5), "the detail is covered")
        app.tabBars.buttons["Today"].tap()
        let viewSession = app.buttons["View session"]
        XCTAssertTrue(viewSession.waitForExistence(timeout: 10))
        viewSession.tap()
        deleteTheWorkout(in: app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(exerciseTitle.waitForExistence(timeout: 5), "History is as it was left")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Go to Today"].waitForExistence(timeout: 10), "the gone detail popped itself")
        XCTAssertFalse(app.staticTexts["history.workout.title"].exists)
    }

    /// The app with the sample workout saved, on Today.
    @MainActor
    private func launchWithASavedWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        saveASampleWorkout(app)
        return app
    }

    /// On a workout's detail: "Delete workout", then the alert's "Delete"; the detail closes.
    @MainActor
    private func deleteTheWorkout(in app: XCUIApplication) {
        let detail = app.staticTexts["history.workout.title"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "the detail is up")
        let delete = app.buttons["history.workout.delete"]
        if !delete.isHittable {
            app.swipeUp()
        }
        delete.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "it asks first")
        confirm.tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 10), "the detail closes")
    }

    /// Starts the Debug menu's sample workout from Today, logs its first set, saves it and closes the receipt.
    @MainActor
    private func saveASampleWorkout(_ app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let sample = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        let logSet = app.buttons["Log set 1"]
        XCTAssertTrue(logSet.waitForExistence(timeout: 10))
        logSet.tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let done = app.buttons["workout.receipt.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10))
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
