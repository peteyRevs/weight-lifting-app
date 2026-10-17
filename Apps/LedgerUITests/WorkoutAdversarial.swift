import XCTest

/// F10 S4 adversarial round 1 (G2), for what only the running app shows: a system dialog of the workout as a
/// lifter and VoiceOver meet it. The Debug menu's "Start sample workout" always asks for the same day, so the
/// conflict dialog cannot be raised from it (test-findings, F10-S4); the finish dialog is the same control and
/// is the one this reads. Nightly only, as every UI test but `Smoke` is.
final class WorkoutAdversarial: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Asking for the sample day again while it runs shows the workout and never the conflict dialog. Then
    /// "End workout?": its tree is printed for the findings, it can be left without choosing by a tap
    /// outside it, which leaves the workout up, and "Keep lifting" does the same.
    @MainActor
    func test_finishDialog_treeAndTheWaysOutOfIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))

        startSampleWorkout(in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        startSampleWorkout(in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["You have a workout in progress"].exists, "the same day is no conflict")

        let finish = app.buttons["workout.header.finish"]
        finish.tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        record(app)

        // A point well away from the dialog's buttons, wherever the system put them.
        let window = app.windows.firstMatch.frame
        let away = discard.frame.midY < window.midY ? 0.85 : 0.2
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: away)).tap()
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5), "a tap outside leaves the dialog")
        XCTAssertTrue(minimize.exists, "and the workout is still up")
        XCTAssertTrue(minimize.isHittable)

        finish.tap()
        let keep = app.buttons["workout.finish.keep"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(keep.waitForNonExistence(timeout: 5))
        XCTAssertTrue(minimize.isHittable, "\"Keep lifting\" leaves the workout up")

        finish.tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 5))
    }

    /// The dialog as the accessibility client sees it, printed for the findings and kept with the result.
    @MainActor
    private func record(_ app: XCUIApplication) {
        print("G2-TREE-BEGIN\n\(app.debugDescription)\nG2-TREE-END")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "End workout? tree"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "End workout? dialog"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens the Debug menu from Today's title and taps "Start sample workout".
    @MainActor
    private func startSampleWorkout(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }
}
