import XCTest

/// F10 S7a adversarial round 2 (G2): the failed save's alert in the running app, through the Debug seam
/// `-LEDGER_UITEST_FAIL_FINISH`: failures in a row across a cover closed and opened again. (That the seam
/// is read only beside `-LEDGER_UITEST` is `UITestSaveFailuresTests`'.) Nightly only, as every UI test but
/// `Smoke` is.
final class WorkoutSaveFailureAdversarial: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Three failures: the first, then "Close", "Minimize" and "Resume workout" (a new cover, a new store
    /// whose attempts count from one again), then "Save workout" fails again and "Try again" fails a third
    /// time. Each failure's alert comes up and answers; the fourth save goes through onto Today.
    @MainActor
    func test_failuresAcrossACoverOpenedAgain_eachShowsTheAlert() {
        let app = launch(["-LEDGER_UITEST", "1", "-LEDGER_UITEST_FAIL_FINISH", "3"])
        startAndAskToSave(in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(answers(alert.buttons["Close"]), "failure 1")
        alert.buttons["Close"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        let minimize = app.buttons["workout.header.minimize"]
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        let resume = app.buttons["Resume workout"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "the workout is still live")
        resume.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // The seam refuses before the host: no end waits, so the new cover's Discard would be a real one.
        XCTAssertTrue(app.buttons["workout.finish.discard"].firstMatch.exists, "a new cover offers Discard (S7a-8)")
        save.tap()
        XCTAssertTrue(answers(alert.buttons["Try again"]), "failure 2, in the new cover")
        alert.buttons["Try again"].tap()
        XCTAssertTrue(answers(alert.buttons["Try again"]), "failure 3, after Try again")
        alert.buttons["Try again"].tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 10), "the live workout is gone: the receipt shows")
        // F10 S7b (edited for the audit): the receipt shows first; its "Done" takes the cover down.
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt")
        app.buttons["workout.receipt.done"].tap()
        XCTAssertTrue(app.buttons["View session"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func startAndAskToSave(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
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
    }

    /// Whether `button` comes up and can be tapped within ten seconds.
    @MainActor
    private func answers(_ button: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: button)
        return XCTWaiter().wait(for: [ready], timeout: 10) == .completed
    }
}
