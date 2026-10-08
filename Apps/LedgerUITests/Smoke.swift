import XCTest

/// Selected by the `PR` test plan as `LedgerUITests/Smoke` (docs/testing-strategy.md §8). F07 criterion 1: the app
/// launches on a fresh database (`-LEDGER_UITEST`) to Today. F10 S4 criterion 10: the workout's cover in the
/// running app, reached through the Debug menu's "Start sample workout" until Today starts workouts (F09).
final class Smoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launchesToToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launch()
        let title = app.staticTexts["today.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Today")
    }

    /// The sample workout starts and its cover goes up over the tabs at 0:00; the time counts; Minimize
    /// takes the cover down and leaves the workout running; asking for the same day again shows that
    /// workout, with the time it has run; Finish, then Discard, ends it and takes the cover down.
    @MainActor
    func test_sampleWorkout_startsCountsMinimizesResumesDiscards() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        startSampleWorkout(in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, "Upper A — Push focus")
        XCTAssertEqual(app.otherElements["workout.header.progress"].value as? String, "Exercise 1 of 5")
        XCTAssertFalse(today.isHittable, "the cover is over the tabs")
        // The elapsed time is drawn by the system's timer text, which VoiceOver is given no time for: the
        // test reads the pixels. It starts at 0:00 and is a different picture within a few seconds.
        let elapsed = app.otherElements["workout.header.elapsed"]
        XCTAssertEqual(elapsed.label, "Elapsed time")
        let atStart = elapsed.screenshot().pngRepresentation
        attachScreenshot(of: app, named: "Workout, just started")
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in elapsed.screenshot().pngRepresentation != atStart },
            object: nil
        )
        wait(for: [counted], timeout: 10)

        minimize.tap()
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        startSampleWorkout(in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the same day again shows the workout that is running")
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["End workout?"].exists)
        XCTAssertTrue(app.buttons["workout.finish.keep"].firstMatch.exists)
        attachScreenshot(of: app, named: "End workout?")
        discard.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        XCTAssertTrue(today.waitForExistence(timeout: 5))
    }

    /// Opens the Debug menu from Today's title and taps "Start sample workout".
    @MainActor
    private func startSampleWorkout(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Kept with the result, so a run shows the screens it checked.
    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
