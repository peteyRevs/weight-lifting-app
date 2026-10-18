import XCTest

/// F11 S14 criterion 24 c, d and f, on screen: the Day editor and the exercise library in the running app, on
/// the seed program's Upper A in week 5 (`Builder` says how the program is put there). Nightly only: the `PR`
/// plan selects `Smoke`.
final class DayEditor: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 24c: a finger on a row opens and closes it (VoiceOver's "expanded" and "collapsed"); on a stepper's "−"
    /// and "+", one step each; on a progression chip; on the drop-set switch.
    @MainActor
    func test_fingerOnARowAStepperAChipAndTheSwitch() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        let row = app.buttons["1, Barbell Bench Press"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let sets = app.descendants(matching: .any)["Sets"].firstMatch
        XCTAssertTrue(sets.waitForExistence(timeout: 5), "the panel opened")
        attachScreenshot(of: app, named: "Day editor, bench press open")
        XCTAssertEqual(sets.value as? String, "5")
        // The field's "−" and "+" are 44 pt buttons at its trailing end, "+" last.
        Self.tap(sets, fromTheTrailingEdge: 22)
        BuilderApp.wait(for: sets, toRead: "6")
        Self.tap(sets, fromTheTrailingEdge: 22 + 44 + 8)
        BuilderApp.wait(for: sets, toRead: "5")

        let double = app.buttons["Double"].firstMatch
        BuilderApp.scrollUntilHittable(double, in: app)
        double.tap()
        let floor = app.descendants(matching: .any)["Rep floor"].firstMatch
        XCTAssertTrue(floor.waitForExistence(timeout: 5), "double progression has a rep floor")

        let dropSet = app.switches["Drop set"].firstMatch
        BuilderApp.scrollUntilHittable(dropSet, in: app)
        XCTAssertEqual(dropSet.value as? String, "0")
        dropSet.tap()
        BuilderApp.wait(for: dropSet, toRead: "1")
        attachScreenshot(of: app, named: "Day editor, double progression and a drop set")

        app.swipeDown()
        row.tap()
        XCTAssertTrue(sets.waitForNonExistence(timeout: 5), "the panel closed")
    }

    /// 24c: "Delete day" asks in an alert (Pete's question 3, A); "Cancel" keeps the day, "Delete" deletes it
    /// and the editor closes once the write is stored; the builder no longer lists the day.
    @MainActor
    func test_deleteAlert_cancelThenDelete() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        let delete = app.buttons["Delete day"]
        BuilderApp.scrollUntilHittable(delete, in: app)
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.label, "Delete Upper A?")
        attachScreenshot(of: app, named: "Delete day alert")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Day name"].exists, "the day stays")
        delete.tap()
        app.alerts.firstMatch.buttons["Delete"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "back on the builder")
        XCTAssertFalse(app.buttons["Upper A — Push focus"].exists)
    }

    /// 18 and 20, on screen: "Program" goes back; the system's swipe back goes back too; the day opened next
    /// shows its own name, not the draft of the one before.
    @MainActor
    func test_backAndSwipeBack_andTheNextDayIsItsOwn() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        let name = app.textFields["Day name"]
        name.tap()
        name.typeText(" draft")
        Self.barButton("Program", in: app).tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5))
        let lowerA = app.buttons["Lower A — Squat focus"].firstMatch
        BuilderApp.scrollUntilHittable(lowerA, in: app)
        lowerA.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Lower A — Squat focus", "nothing of Upper A's draft")
        Self.swipeBack(in: app)
        // Known (S14 notes, open question 1): with the navigation bar hidden the system's swipe back does not pop
        // the Day editor; the same swipe pops Settings (`test_swipeBack_control_popsAScreenWithTheSystemBar`).
        // Strict: this fails as soon as the swipe pops, so the mark goes with the fix.
        XCTExpectFailure("The hidden navigation bar takes the system's swipe back away (criterion 20)") {
            XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "the swipe back pops it")
        }
        Self.barButton("Program", in: app).tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Upper A — Push focus draft"].exists, "the draft was stored as typed")
    }

    /// The control of the swipe above: the same synthesized swipe pops Today's Settings, a pushed screen that
    /// keeps the system's navigation bar. So a failure above is the Day editor's, not the gesture's.
    @MainActor
    func test_swipeBack_control_popsAScreenWithTheSystemBar() {
        let app = BuilderApp.launch(at: Builder.week5)
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        Self.swipeBack(in: app)
        XCTAssertTrue(app.staticTexts["settings.title"].waitForNonExistence(timeout: 5), "the swipe back pops it")
    }

    /// 24d: the library: a query typed, a chip tapped, three exercises picked and added, in the order picked.
    @MainActor
    func test_library_queryChipThreePicks() {
        let app = BuilderApp.launch(at: Builder.week5)
        BuilderApp.openUpperA(in: app)
        let open = app.buttons["+ Add exercise from library"]
        BuilderApp.scrollUntilHittable(open, in: app)
        open.tap()
        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.buttons["Muscle: Back"].firstMatch.tap()
        search.tap()
        search.typeText("row")
        attachScreenshot(of: app, named: "Library, back, row")
        let picked = ["Barbell Row", "Seated Cable Row", "Chest-Supported Row"]
        for exercise in picked {
            let row = app.buttons[exercise].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), exercise)
            row.tap()
            XCTAssertTrue(row.isSelected, "\(exercise) is picked")
        }
        app.buttons["Add 3 exercises"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "the sheet closed")
        for (place, exercise) in picked.enumerated() {
            XCTAssertTrue(app.buttons["\(place + 5), \(exercise)"].firstMatch.exists, "\(exercise) is row \(place + 5)")
        }
        attachScreenshot(of: app, named: "Day editor, three added")
        open.tap()
        XCTAssertTrue(app.buttons["Muscle: Back"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Muscle: Back"].firstMatch.isSelected, "the chip is kept between openings")
        XCTAssertEqual(search.value as? String, "Search exercises", "the query was emptied")
        search.swipeDown(velocity: .fast)
    }

    /// 24f: at an accessibility size the Day editor's stops stand in the bar and the one scroll view in the
    /// table's order, and the foot of the page can be reached and used.
    @MainActor
    func test_atAnAccessibilitySize_readsItsStopsInOrder() {
        let app = BuilderApp.launch(at: Builder.week5, textSize: "UICTContentSizeCategoryAccessibilityXL")
        BuilderApp.openUpperA(in: app)
        let stops = [
            Self.barButton("Program", in: app), app.staticTexts["DAY 1 OF 4"], app.textFields["Day name"],
            app.buttons["1, Barbell Bench Press"].firstMatch, app.buttons["4B, Cable Lateral Raise"].firstMatch,
            app.buttons["+ Add exercise from library"], app.buttons["Delete day"]
        ]
        for stop in stops {
            XCTAssertTrue(stop.waitForExistence(timeout: 10), "\(stop)")
        }
        let tops = stops.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "the order on the page is the order of the table")
        XCTAssertLessThanOrEqual(
            app.buttons["Done"].frame.maxY,
            app.scrollViews.firstMatch.frame.minY,
            "the bar is pinned"
        )
        attachScreenshot(of: app, named: "Day editor, accessibility size")
        BuilderApp.scrollUntilHittable(stops[stops.count - 1], in: app)
        stops[stops.count - 1].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "the last stop works")
        app.alerts.firstMatch.buttons["Cancel"].tap()
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension DayEditor {
    /// The system's swipe back, from the screen's leading edge.
    @MainActor
    static func swipeBack(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    /// The Day editor's bar button of this label, not the tab bar's "Program".
    @MainActor
    static func barButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let bar = app.tabBars.firstMatch.frame
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.first { !bar.intersects($0.frame) } ?? app.buttons[label].firstMatch
    }

    /// Taps `element` `points` in from its trailing edge, on its middle line.
    @MainActor
    static func tap(_ element: XCUIElement, fromTheTrailingEdge points: CGFloat) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -points, dy: 0))
            .tap()
    }
}
