import XCTest

/// F11 S14 adversarial round 1, on screen: the Program tab in the running app (criteria 9, 20 and 23, ruling R10,
/// Pete's question 2). Nightly only: the `PR` plan selects `Smoke`. On the seed program in week 5, as `Builder` and
/// `DayEditor` put it there.
final class ProgramTabAdversarial: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Today's "Edit this week" asks the builder for week 5 once. The lifter then picks week 6, opens a day and
    /// comes back with "Done", then goes to Today and back: week 6 stays selected each time.
    @MainActor
    func test_editThisWeek_thenAnotherWeek_isKeptAfterTheDayEditorAndATabSwitch() {
        // A rest day of week 5 (Thursday 2026-09-17), whose card carries "Edit this week".
        let app = BuilderApp.launch(at: "2026-09-17T12:00:00Z")
        let edit = app.buttons["Edit this week"].firstMatch
        BuilderApp.scrollUntilHittable(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Week 5"].isSelected, "the week asked for")
        app.buttons["Week 6"].tap()
        XCTAssertTrue(app.buttons["Week 6"].isSelected)
        let card = app.buttons["Upper A — Push focus"].firstMatch
        BuilderApp.scrollUntilHittable(card, in: app)
        card.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5))
        Self.barButton("Done", in: app).tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5))
        attach(app, named: "Back from the Day editor")
        XCTAssertTrue(app.buttons["Week 6"].isSelected, "back from the Day editor: the week the lifter picked")
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5))
        attach(app, named: "Back from Today")
        XCTAssertTrue(app.buttons["Week 6"].isSelected, "back from Today: the week the lifter picked")
    }

    /// Criterion 20 on a Day editor freshly opened (no field had the focus): the swipe from the leading edge.
    @MainActor
    func test_edgeSwipe_onAFreshDayEditor_pops() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        Self.drag(in: app, from: 0, to: 0.85, atHeight: 0.3)
        // Sanctioned edit (S14 fix round 1, ruling on F11-S14-2): criterion 20 is open, its fix a follow-up with a
        // UIKit helper in `LedgerDesign`. Strict: this fails as soon as the swipe pops, so the mark goes with it.
        XCTExpectFailure("F11-S14-2: the hidden navigation bar takes the system's swipe back away") {
            XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "the edge swipe pops it")
        }
        attach(app, named: "After the edge swipe")
    }

    /// iOS 26's swipe back from inside the content (not only the edge), on the Day editor's header.
    @MainActor
    func test_contentSwipe_onAFreshDayEditor_pops() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        Self.drag(in: app, from: 0.3, to: 0.95, atHeight: 0.3)
        // Sanctioned edit (S14 fix round 1, ruling on F11-S14-2): criterion 20 is open, its fix a follow-up with a
        // UIKit helper in `LedgerDesign`. Strict: this fails as soon as the swipe pops, so the mark goes with it.
        XCTExpectFailure("F11-S14-2: the hidden navigation bar takes the system's swipe back away") {
            XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "the content swipe pops it")
        }
        attach(app, named: "After the content swipe")
    }

    @MainActor
    private static func drag(in app: XCUIApplication, from start: CGFloat, to end: CGFloat, atHeight height: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: start, dy: height)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: end, dy: height)),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    /// The Day editor's bar button of this label, not the tab bar's.
    @MainActor
    private static func barButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let bar = app.tabBars.firstMatch.frame
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.first { !bar.intersects($0.frame) } ?? app.buttons[label].firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
