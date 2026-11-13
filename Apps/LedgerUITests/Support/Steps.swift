import XCTest

/// F15's steps through the running app (S1, question 7): what `Smoke.test_onboardToFirstSet` and `Flows` do
/// again and again, said once, so the tests read as the lifter's path. The older UI tests keep their own private
/// copies of these; moving them here is a later chore's.
///
/// Each step waits only with `waitForExistence` or a predicate, never a sleep, and fails at the step's own
/// assertion with what it waited for. `attachScreenshot(named:)` is kept with the result at each stage, so a
/// failure in a long flow shows where it stopped (risk R5).
@MainActor
struct Steps {
    let app: XCUIApplication
    private let test: XCTestCase

    /// Launches the app as a UI test (`-LEDGER_UITEST 1`, a fresh database), with `arguments` after it.
    init(launching arguments: [String] = [], for test: XCTestCase) {
        app = XCUIApplication.fresh(arguments)
        self.test = test
        app.launch()
    }

    var todayTitle: XCUIElement {
        app.staticTexts["today.title"]
    }

    var minimize: XCUIElement {
        app.buttons["workout.header.minimize"]
    }

    var skip: XCUIElement {
        app.buttons["workout.rest.skip"]
    }

    var cardTitle: XCUIElement {
        app.staticTexts["workout.card.title"]
    }

    // MARK: - Today and the workout's cover

    /// Today's own "Start workout", as a lifter starts the day's session: the cover goes up.
    func startFromToday() {
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Today offers the day's session")
        start.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the workout's cover is up")
    }

    /// The check of the shown exercise's row `set` ("1", "A1"): the row reads logged.
    func logSet(_ set: String) {
        let check = app.buttons["Log set \(set)"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "set \(set) can be logged")
        check.tap()
        XCTAssertTrue(app.buttons["Undo set \(set)"].waitForExistence(timeout: 5), "set \(set) is logged")
    }

    /// "Skip rest" on the panel a logged set brought up; the panel goes.
    func skipRest() {
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "a logged set starts a rest")
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "Skip rest takes the panel away")
    }

    /// "Finish", then "Save workout": the receipt shows in the cover.
    func finishAndSave() {
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "End workout? is up")
        XCTAssertTrue(save.isEnabled, "a workout with a set logged can be saved")
        save.tap()
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt shows")
    }

    /// The receipt's "Done": the cover goes down onto the tabs.
    func closeReceipt() {
        let done = app.buttons["workout.receipt.done"]
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10), "the cover is down")
        XCTAssertTrue(becomesHittable(todayTitle), "the tabs are back")
    }

    /// "Finish", then "Discard": the cover goes down and nothing is left running (ruling A6).
    func discard() {
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "End workout? is up")
        discard.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5), "the cover is down")
        XCTAssertTrue(becomesHittable(todayTitle), "the tabs are back")
    }

    // MARK: - Finding and waiting

    /// The first element of any kind whose label starts with `prefix`: a combined row ("Back Squat, 5 × 5 …").
    func element(startingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The first element of any kind whose label holds `text`.
    func element(saying text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Whether `element` reads `label` within five seconds.
    func reads(_ element: XCUIElement, _ label: String) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [reads], timeout: 5) == .completed
    }

    /// Whether `element` can be tapped within five seconds: an element under the cover exists all along, so only
    /// this says the cover is down.
    func becomesHittable(_ element: XCUIElement) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [hittable], timeout: 5) == .completed
    }

    /// Swipes the screen's first scroll view up until `element` can be tapped, at most ten times.
    func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0 ..< 10 where !(element.exists && element.isHittable) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists, "\(element) is not on the screen")
        XCTAssertTrue(element.isHittable, "\(element) cannot be reached")
    }

    /// Kept with the result, so a run shows the screens it checked.
    func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
