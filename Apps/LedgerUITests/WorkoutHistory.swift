import XCTest

/// F13 S1, criteria 1 and 6, on screen: the History tab in the running app. A sample workout with one set is saved,
/// then History lists it under its week as one button, the workout's name with its meta as its value; a tap pushes
/// its detail (a placeholder until F13 S2) on History's stack, and back returns to the list. Nightly only: the `PR`
/// plan selects `Smoke`.
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
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "its detail is pushed")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists, "the list is as it was left")
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
