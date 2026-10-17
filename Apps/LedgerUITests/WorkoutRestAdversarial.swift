import XCTest

/// F10 S6 adversarial round 1 (G2), for what only the running app shows of the rest panel: the app's own
/// composition (the real host, the live haptics, no notification client), `WorkoutRoot`'s tasks, and the
/// system's clocks. A set is logged; two quick "+30s" are a minute; the panel is not on Today; a cover
/// opened again mid-rest, and an app back from the background, read the wall clock's time left; "Skip
/// rest" takes the panel away. The sample workout from the Debug menu, discarded at the end. Nightly only.
///
/// Not here: a rest's end. The sample's shortest rest is 150 s, every launch starts on a database of its
/// own, and the app's date can be moved only at launch, so no test reaches "Rest over" in seconds.
final class WorkoutRestAdversarial: XCTestCase {
    override func setUpWithError() throws {
        // A finding must not leave a workout running for the next test: each test discards at its end.
        continueAfterFailure = true
    }

    @MainActor
    func test_rest_twoQuickExtends_minimized_backgrounded_skipped() throws {
        let app = launch()
        startSampleWorkout(in: app)
        let log = app.buttons["Log set 1"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        let extend = app.buttons["workout.rest.extend"]
        let skip = app.buttons["workout.rest.skip"]
        XCTAssertFalse(skip.exists, "no set is logged: no panel")
        log.tap()
        guard skip.waitForExistence(timeout: 5) else {
            XCTFail("a logged set brought up no rest panel")
            discard(in: app)
            return
        }
        let start = try secondsLeft(in: status)
        XCTAssertTrue((141 ... 150).contains(start), "the bench press rests 150 s: \(start)")

        // Two quick taps on "+30s" are a minute, each applied once.
        extend.tap()
        extend.tap()
        wait("two +30s to show", timeout: 5) { (try? self.secondsLeft(in: status)).map { $0 > start + 45 } ?? false }
        let extended = try secondsLeft(in: status)
        XCTAssertLessThanOrEqual(extended, start + 60, "two taps added more than a minute")
        attachScreenshot(of: app, named: "Rest panel, after two +30s")

        let reopened = try minimizeAndReopen(app, from: extended)
        try backgroundAndReturn(app, from: reopened)

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo set 1"].exists, "skipping the rest took the set back")
        discard(in: app)
    }

    /// At the largest text size (the brief asks for Dynamic Type to AX5) on the plan's iPhone 17 the panel
    /// is compact (ruling 17 after round 1: no ring, no next-set line): its buttons are on screen and about
    /// 314 pt of the page show over it, as the hosted model says (`screen_roomIsMeasured`: 304 to 324 pt).
    /// Before the compact panel it was 64 pt.
    @MainActor
    func test_rest_atTheLargestTextSize_leavesSomeOfThePage() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        startSampleWorkout(in: app)
        let log = app.buttons["Log set 1"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.tap()
        let skip = app.buttons["workout.rest.skip"]
        guard skip.waitForExistence(timeout: 5) else {
            XCTFail("a logged set brought up no rest panel")
            discard(in: app)
            return
        }
        attachScreenshot(of: app, named: "Rest panel, the largest text size")
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        let page = app.scrollViews.containing(.staticText, identifier: "workout.card.title").firstMatch
        // The panel's card begins its inner margin, 16 pt, over the stop that reads the time.
        let strip = status.frame.minY - 16 - page.frame.minY
        XCTAssertTrue(skip.isHittable, "Skip rest is not on screen")
        XCTAssertTrue(app.buttons["workout.rest.extend"].isHittable, "+30s is not on screen")
        XCTAssertLessThanOrEqual(skip.frame.maxY, app.frame.maxY, "Skip rest ends below the screen")
        XCTAssertGreaterThanOrEqual(strip, 44, "the page shows \(Int(strip)) pt over the rest panel")
        // The hosted model's 313.7 pt, to the few points a status bar or a margin can differ by.
        XCTAssertEqual(strip, 314, accuracy: 15, "the app and the hosted model disagree about the page's room")
        XCTAssertFalse(app.staticTexts["Set 2 · 180 lb × 5"].exists, "the next set is drawn at the largest size")
        XCTAssertTrue(status.label.hasPrefix("Resting, Set 2, "), "and VoiceOver still reads it: \(status.label)")
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        discard(in: app)
    }
}

private extension WorkoutRestAdversarial {
    /// Minimized mid-rest: no panel on Today; opened again, the panel reads the wall clock's time left,
    /// which is returned.
    @MainActor
    private func minimizeAndReopen(_ app: XCUIApplication, from extended: Int) throws -> Int {
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        let skip = app.buttons["workout.rest.skip"]
        let minimize = app.buttons["workout.header.minimize"]
        let minimizedAt = Date()
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        XCTAssertFalse(skip.exists, "the rest panel is on Today")
        letPass(3)
        startSampleWorkout(in: app)
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "the cover opened again shows no rest panel")
        let reopened = try secondsLeft(in: status)
        let away = Int(Date().timeIntervalSince(minimizedAt).rounded(.up))
        XCTAssertLessThanOrEqual(reopened, extended - 3, "three seconds away, and the rest lost none")
        XCTAssertGreaterThanOrEqual(reopened, extended - away - 3, "the rest lost more than the time away")
        XCTAssertTrue(status.label.hasPrefix("Resting, Set 2, "), status.label)
        return reopened
    }

    /// In the background for six seconds: on the return the panel has lost them, and goes on.
    @MainActor
    private func backgroundAndReturn(_ app: XCUIApplication, from reopened: Int) throws {
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        let skip = app.buttons["workout.rest.skip"]
        let leftAt = Date()
        XCUIDevice.shared.press(.home)
        letPass(6)
        app.activate()
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        wait("the panel to read the time after the background", timeout: 3) {
            (try? self.secondsLeft(in: status)).map { $0 <= reopened - 6 } ?? false
        }
        let returned = try secondsLeft(in: status)
        let gone = Int(Date().timeIntervalSince(leftAt).rounded(.up))
        XCTAssertGreaterThanOrEqual(returned, reopened - gone - 3, "the rest lost more than the time away")
        wait("the rest to go on counting", timeout: 5) {
            (try? self.secondsLeft(in: status)).map { $0 < returned } ?? false
        }
        attachScreenshot(of: app, named: "Rest panel, back from the background")
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
    private func wait(_ what: String, timeout: TimeInterval, until holds: @escaping @MainActor () -> Bool) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { holds() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "never came: \(what)")
    }

    /// Lets `seconds` of the device's time go by: the app is what is under test, and it is doing nothing.
    @MainActor
    private func letPass(_ seconds: TimeInterval) {
        let never = XCTestExpectation(description: "time to pass")
        never.isInverted = true
        _ = XCTWaiter().wait(for: [never], timeout: seconds)
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        return app
    }

    /// Opens the Debug menu from Today's title and taps "Start sample workout"; with a workout of the same
    /// day already live, that opens its cover again.
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
