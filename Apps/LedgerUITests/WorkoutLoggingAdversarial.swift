import XCTest

/// F10 S5 adversarial round 1 (G2), for what only the running app shows: a person's double tap on a check,
/// which lands on the screen as it is redrawn between the two taps, and where the page stands in its real
/// scroll view after a jump. The sample workout from the Debug menu, discarded at the end. Nightly only, as
/// every UI test but `Smoke` is.
final class WorkoutLoggingAdversarial: XCTestCase {
    override func setUpWithError() throws {
        // A finding must not leave a workout running for the next test: each test discards at its end.
        continueAfterFailure = true
    }

    /// The system's own double tap (`doubleTap()`, two touches some tens of milliseconds apart) on a check
    /// logs the set once: the second touch comes before the row is redrawn. Criterion 7, in the running app.
    @MainActor
    func test_doubleTapOnACheck_logsTheSetOnce() {
        let app = launch()
        startSampleWorkout(in: app)
        let log = app.buttons["Log set 1"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.doubleTap()
        let wasLogged = app.buttons["Undo set 1"].waitForExistence(timeout: 3)
        attachScreenshot(of: app, named: "After a double tap on the first check")
        XCTAssertTrue(wasLogged, "after a double tap the first set is not logged")
        XCTAssertFalse(app.buttons["Log set 1"].exists, "the first row's check offers to log it again")
        XCTAssertFalse(app.buttons["Undo set 2"].exists, "the second tap logged the next row")
        discard(in: app)
    }

    /// F10-S5-6 (round 1's question; criterion 18 since): a second touch on the same spot that comes after
    /// the row was redrawn, less than a second after the first, does not take the set back. Two separate
    /// taps, as fast as XCUITest makes them, stand for a slow or nervous double tap: the first logs, the row
    /// is drawn done, the second lands on "Undo set 1" and is ignored.
    ///
    /// Round 2: the guard is one second and XCUITest's two taps have been 0.78 s apart, so on a slow runner
    /// the second can fall outside it and rightly un-log. The time from before the first tap to after the
    /// second is longer than the time between the touches: under a second, the touches were inside the guard
    /// and the set must be logged; otherwise the run says nothing about the guard and the test is skipped.
    @MainActor
    func test_secondTouchOnTheSameCheck_doesNotLoseTheSet() throws {
        let app = launch()
        startSampleWorkout(in: app)
        let log = app.buttons["Log set 1"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        // A place on the screen, not on the element: the second touch goes where the first went.
        let spot = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: log.frame.midX, dy: log.frame.midY))
        let started = Date()
        spot.tap()
        spot.tap()
        let apart = Date().timeIntervalSince(started)
        // Let whatever the two touches came to be drawn, then read the page.
        _ = app.buttons["Undo set 2"].waitForExistence(timeout: 2)
        attachScreenshot(of: app, named: "After two touches on the first check")
        let isLogged = app.buttons["Undo set 1"].exists
        discard(in: app)
        try XCTSkipIf(apart >= 1, "the two taps took \(String(format: "%.2f", apart)) s: not a second touch")
        XCTAssertTrue(
            isLogged,
            "two touches on the first check within \(String(format: "%.2f", apart)) s left its set not logged"
        )
    }

    /// FINDING F10-S5-5 (the reviewer's S-2): after a jump from "REMAINING" at an accessibility text size
    /// the new exercise's name is above the screen: the page keeps the scroll position the list was tapped at.
    @MainActor
    func test_jumpFromRemaining_showsTheNewExercisesName() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        startSampleWorkout(in: app)
        let title = app.staticTexts["workout.card.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable, "the first exercise's name is on screen when the cover opens")

        app.buttons["workout.remaining.row.4"].tap()
        let reads = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Cable Lateral Raise"), object: title
        )
        XCTAssertEqual(XCTWaiter().wait(for: [reads], timeout: 5), .completed)
        attachScreenshot(of: app, named: "After a jump at an accessibility size")
        // The cover's own page: Today's scroll view is still in the tree under the cover (since F09 S5), and
        // comes first in it, so `scrollViews.firstMatch` was Today's (G2, F10 S6).
        let pages = app.scrollViews.containing(.staticText, identifier: "workout.card.title")
        XCTAssertEqual(pages.count, 1, "the cover's page is one scroll view")
        let scroll = pages.firstMatch.frame
        XCTAssertLessThanOrEqual(
            app.buttons["workout.header.finish"].frame.maxY,
            scroll.minY,
            "the page is under the header"
        )
        XCTAssertGreaterThanOrEqual(title.frame.minY, scroll.minY, "the name is above the page's top edge")
        XCTAssertTrue(title.isHittable, "the name of the exercise jumped to is not on screen")
        XCTAssertTrue(app.staticTexts["Exercise 5 of 5"].isHittable, "nor is its place")
        discard(in: app)
    }
}

private extension WorkoutLoggingAdversarial {
    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        return app
    }

    /// Opens the Debug menu from Today's title and taps "Start sample workout".
    @MainActor
    private func startSampleWorkout(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// "Finish", then "Discard": the cover goes down and nothing is left running for the next test.
    @MainActor
    private func discard(in app: XCUIApplication) {
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 5))
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
