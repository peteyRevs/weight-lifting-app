import XCTest

/// The watch's steps through the running app (F18 S7), as the iPhone's `Steps` (LedgerUITests/Support): each waits
/// only with `waitForExistence` or a predicate, never a sleep, and fails at its own assertion with what it waited for.
@MainActor
struct WatchSteps {
    /// Monday 2026-09-14, noon UTC: week 5 of the seed program (from Monday 2026-08-17), whose Mondays are Upper A.
    static let monday = "2026-09-14T12:00:00Z"
    /// A UI test's watch with the seed program, on that Monday (`WatchUITest`).
    static let seededMonday = ["-LEDGER_UITEST_PROGRAM", "seed", "-LEDGER_UITEST_NOW", monday]
    /// The seed program's Monday: its title on the screen before a workout.
    static let upperA = "Upper A — Push focus"

    let app: XCUIApplication
    private let test: XCTestCase

    /// Launches the app as a UI test (`-LEDGER_UITEST 1`: a fresh database and a scripted Health store), with
    /// `arguments` after it, and waits for the screen before a workout.
    init(launching arguments: [String] = [], for test: XCTestCase) {
        app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        self.test = test
        app.launch()
        XCTAssertTrue(todayTitle.waitForExistence(timeout: 20), "the screen before a workout")
    }

    var todayTitle: XCUIElement {
        app.staticTexts["today.title"]
    }

    var setLabel: XCUIElement {
        app.staticTexts["workout.ready.setLabel"]
    }

    var restTitle: XCUIElement {
        app.staticTexts["workout.rest.title"]
    }

    /// Any element by its identifier, whatever its type: a line VoiceOver reads as one element.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Whether `element`'s label becomes `label` within `timeout`.
    func reads(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        wait(for: element, "label == %@", label, timeout: timeout)
    }

    /// Whether `element` comes to match `format` with `argument` within `timeout`.
    func wait(for element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, argument), object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps the button `identifier` once it is on screen, swiping the page up to it when a large text scrolls.
    func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(identifier) is shown", file: file, line: line)
        for _ in 0 ..< 5 where !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }

    /// "Start" on the seed program's Monday: the set screen of its first set.
    func start() {
        XCTAssertTrue(reads(todayTitle, Self.upperA), "today is Upper A, not \(todayTitle.label)")
        tap("today.start")
        XCTAssertTrue(setLabel.waitForExistence(timeout: 10), "Start shows the set to log")
    }

    /// The session list, then "End workout": the end overlay.
    func openEnd() {
        tap("workout.ready.exercise")
        tap("workout.list.end")
        XCTAssertTrue(app.staticTexts["workout.end.title"].waitForExistence(timeout: 5), "End workout? is up")
    }

    /// Kept with the result, so a run shows where it got to.
    func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
