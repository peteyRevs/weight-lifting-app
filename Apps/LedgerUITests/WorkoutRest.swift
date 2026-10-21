import XCTest

/// F10 S6, criterion 15: the rest panel in the running app. The sample workout from the Debug menu logs a
/// set, and the panel floats over the page's end: its time left is read in words and counts down by
/// itself, "+30s" adds half a minute, "Skip rest" takes the panel away, and the next logged set brings it
/// back. The page under it can still be scrolled and used. Nightly only, as every UI test but `Smoke` is.
///
/// The sample is the seed program's Upper A, whose bench press rests 150 s: the tests never wait for a
/// rest's end, which the store's tests show with a clock of their own.
final class WorkoutRest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_rest_countsDown_extends_skips_andComesBack() throws {
        let app = launch()
        startSampleWorkout(in: app)
        XCTAssertTrue(app.staticTexts["workout.card.title"].waitForExistence(timeout: 10))
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        let extend = app.buttons["workout.rest.extend"]
        let skip = app.buttons["workout.rest.skip"]
        XCTAssertFalse(skip.exists, "no set is logged: no rest, no panel")

        app.buttons["Log set 1"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertEqual(skip.label, "Skip rest")
        XCTAssertEqual(extend.label, "Add 30 seconds", "+30s is read by what it does")
        XCTAssertTrue(status.label.hasPrefix("Resting, Set 2, "), status.label)
        let start = try secondsLeft(in: status)
        XCTAssertGreaterThan(start, 140)
        XCTAssertLessThanOrEqual(start, 150)
        attachScreenshot(of: app, named: "Rest panel, resting")

        // It counts down by itself, and "+30s" adds half a minute to what is left.
        wait(for: status, toHaveLessThan: start)
        let before = try secondsLeft(in: status)
        extend.tap()
        wait(for: status, toHaveMoreThan: before + 20)
        let extended = try secondsLeft(in: status)
        XCTAssertLessThanOrEqual(extended, before + 30)
        attachScreenshot(of: app, named: "Rest panel, after +30s")

        // The page under the panel still answers: the shown row's check is clear of it.
        XCTAssertTrue(app.buttons["Log set 2"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["Log set 2"].frame.maxY, status.frame.minY)

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertFalse(extend.exists)
        XCTAssertTrue(app.buttons["Undo set 1"].exists, "skipping the rest takes back no set")

        // The next logged set starts its own rest.
        app.buttons["Log set 2"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Resting, Set 3, "), status.label)
        XCTAssertGreaterThan(try secondsLeft(in: status), 140)

        discard(in: app)
    }

    /// At an accessibility text size the panel is tall, about half the screen: the page's last control can
    /// still be scrolled clear of it and used, and the panel's own buttons are on screen.
    @MainActor
    func test_rest_atAnAccessibilitySize_thePageScrollsClearOfThePanel() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        // Today's own page is a scroll view, and it is still counted under the cover.
        let underTheCover = app.scrollViews.count
        startSampleWorkout(in: app)
        XCTAssertTrue(app.staticTexts["workout.card.title"].waitForExistence(timeout: 10))
        app.buttons["Log set 1"].tap()
        let skip = app.buttons["workout.rest.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable)
        XCTAssertTrue(app.buttons["workout.rest.extend"].isHittable)
        let page = app.scrollViews.containing(.staticText, identifier: "workout.card.title").firstMatch
        XCTAssertEqual(app.scrollViews.count, underTheCover + 1, "the panel holds no scroll view of its own")
        attachScreenshot(of: app, named: "Rest panel, accessibility size")

        // The page's end is under the panel. Scrolled to its end, its last row stands clear of the panel,
        // and answers.
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        XCTAssertGreaterThan(status.frame.minY, app.buttons["workout.header.finish"].frame.maxY, "under the header")
        let last = app.buttons["workout.remaining.row.4"]
        // The page is dragged where it can be seen, between the header and the panel: the panel itself
        // does not scroll it.
        let visible = (status.frame.minY - page.frame.minY) / page.frame.height
        for _ in 0 ..< 20 where last.frame.maxY > status.frame.minY {
            let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: visible * 0.9))
            from.press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)))
        }
        XCTAssertLessThanOrEqual(last.frame.maxY, status.frame.minY + 1, "the last row is clear of the panel")
        XCTAssertTrue(last.isHittable)
        attachScreenshot(of: app, named: "Rest panel, accessibility size, the page's end")
        last.tap()
        let title = app.staticTexts["workout.card.title"]
        let jumped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Cable Lateral Raise"), object: title
        )
        XCTAssertEqual(XCTWaiter().wait(for: [jumped], timeout: 5), .completed, title.label)
        XCTAssertTrue(skip.exists, "a jump ends no rest")

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        discard(in: app)
    }

    /// The time left that VoiceOver reads for the panel, in seconds: "2 minutes, 30 seconds" is 150.
    @MainActor
    private func secondsLeft(in status: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(status.value as? String, "the panel reads no time left")
        XCTAssertFalse(value.contains(":"), "the time is read in words: \(value)")
        var seconds = 0
        for part in value.split(separator: ",") {
            let words = part.split(separator: " ")
            let number = try XCTUnwrap(words.first.flatMap { Int($0) }, "not a duration: \(value)")
            seconds += (words.last?.hasPrefix("minute") ?? false) ? number * 60 : number
        }
        return seconds
    }

    @MainActor
    private func wait(for status: XCUIElement, toHaveLessThan seconds: Int) {
        wait(for: status, timeout: 5, "the rest still has \(seconds) s") {
            (try? self.secondsLeft(in: status)).map { $0 < seconds } ?? false
        }
    }

    @MainActor
    private func wait(for status: XCUIElement, toHaveMoreThan seconds: Int) {
        wait(for: status, timeout: 5, "the rest has no more than \(seconds) s") {
            (try? self.secondsLeft(in: status)).map { $0 > seconds } ?? false
        }
    }

    @MainActor
    private func wait(
        for status: XCUIElement,
        timeout: TimeInterval,
        _ message: String,
        until holds: @escaping @MainActor () -> Bool
    ) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { holds() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, message)
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
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
