import XCTest

/// F10 S7a, fix round 1 (G3-2, S7a-2, S7a-3): a save that fails, in the running app. The Debug launch argument
/// `-LEDGER_UITEST_FAIL_FINISH <count>` makes the session's first `count` saves fail before they reach the
/// host (`UITestSaveFailures`). Nightly only, as every UI test but `Smoke` is.
///
/// The app's clock is the Monday of the seed program's first week, so the saved sample is today's Logged card.
final class WorkoutSaveFailure: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Three failures in a row: after the first and after each "Try again" the alert comes back, every time;
    /// the fourth save goes through and Today shows the session logged.
    @MainActor
    func test_tryAgain_eachFailureShowsTheAlertAgain_thenSaves() {
        let app = launchAndAskToSave(failures: 3)
        let alert = app.alerts.firstMatch
        for attempt in 1 ... 3 {
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "the alert of failure \(attempt)")
            XCTAssertTrue(alert.staticTexts["Couldn't save this workout"].exists)
            XCTAssertTrue(alert.buttons["Close"].exists)
            XCTAssertFalse(alert.buttons["Discard"].exists, "no Discard on a failed save (O3)")
            XCTAssertFalse(app.buttons["workout.finish.save"].exists, "the sheet is down")
            alert.buttons["Try again"].tap()
            if attempt < 3 {
                // The next failure's alert is a new one: wait for it to be up and answering.
                let back = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == true AND hittable == true"),
                    object: alert.buttons["Try again"]
                )
                XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 10), .completed, "failure \(attempt + 1) shown")
            }
        }
        XCTAssertTrue(
            app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 10),
            "the live workout is gone: the receipt shows"
        )
        // F10 S7b (edited for the audit): the receipt shows first; its "Done" takes the cover down.
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt")
        app.buttons["workout.receipt.done"].tap()
        XCTAssertTrue(app.buttons["View session"].waitForExistence(timeout: 5), "Today shows the session logged")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// After a failed save and "Close" the sheet offers no "Discard" (the session would save the workout
    /// it was asked to discard); "Save workout" then saves it.
    @MainActor
    func test_close_thenTheSheetOffersNoDiscard_andSaveSaves() {
        let app = launchAndAskToSave(failures: 1)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Close"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.isHittable, "the cover answers again")
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout.finish.discard"].exists, "no Discard once a save was asked for")
        XCTAssertTrue(app.buttons["workout.finish.keep"].firstMatch.exists)
        save.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 10))
        // F10 S7b (edited for the audit): the receipt shows first; its "Done" takes the cover down.
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt")
        app.buttons["workout.receipt.done"].tap()
        XCTAssertTrue(app.buttons["View session"].waitForExistence(timeout: 5))
    }

    /// The sample workout started, one set logged, "Finish" and "Save workout" tapped.
    @MainActor
    private func launchAndAskToSave(failures: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z",
            "-LEDGER_UITEST_FAIL_FINISH", "\(failures)"
        ]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        app.buttons["Log set 1"].tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        return app
    }
}
