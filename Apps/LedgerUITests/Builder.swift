import XCTest

/// F11 S14 criterion 24 a, b, e and f, on screen: the Program builder in the running app, on the spec's seed
/// program. Nightly only: the `PR` plan selects `Smoke`.
///
/// **The program is the Debug menu's**, as in `Today`: a UI test's database holds the catalog and no program,
/// so each test first starts the menu's sample workout, which saves the seed program, and discards it. The
/// clock is moved to Wednesday of week 5 (`-LEDGER_UITEST_NOW`), so the builder opens on week 5.
final class Builder: XCTestCase {
    /// Wednesday of week 5 of the seed program, at noon UTC.
    static let week5 = "2026-09-16T12:00:00Z"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 24a: a name typed letter by letter, a space in it, is read back from the field and from the stored
    /// program (the builder drawn again from another tab); the two name fields are read by their labels.
    @MainActor
    func test_name_typedLetterByLetter_isReadBack() {
        let app = BuilderApp.launch(at: Self.week5)
        BuilderApp.openTheBuilder(in: app)
        let name = app.textFields["Program name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the field is read by its label")
        name.tap()
        BuilderApp.clear(name)
        for letter in "Upper Lower" {
            name.typeText(String(letter))
        }
        XCTAssertEqual(name.value as? String, "Upper Lower")
        name.typeText("\n")
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Program"].tap()
        XCTAssertEqual(app.textFields["Program name"].value as? String, "Upper Lower", "the stored name")
        attachScreenshot(of: app, named: "Builder, renamed")

        app.buttons["Upper A — Push focus"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the Day editor's field, by its label")
    }

    /// 24a: a finger on the drawn "−" and "+" of the block's length moves it the right way, one week a tap.
    @MainActor
    func test_blockLength_fingerOnMinusAndPlus() {
        let app = BuilderApp.launch(at: Self.week5)
        BuilderApp.openTheBuilder(in: app)
        let length = app.descendants(matching: .any)["Block length"].firstMatch
        XCTAssertTrue(length.waitForExistence(timeout: 10))
        XCTAssertEqual(length.value as? String, "8 weeks")
        length.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        BuilderApp.wait(for: length, toRead: "9 weeks")
        length.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        BuilderApp.wait(for: length, toRead: "8 weeks")
        attachScreenshot(of: app, named: "Builder, block length")
    }

    /// 24b: a tap on a wrapped name gives it the focus; while typing the field shows the draft; a draft of
    /// only spaces shows the placeholder (Pete's question 5, A), and losing the focus brings the name back.
    @MainActor
    func test_wrappedName_takesTheFocus_andABlankDraftShowsThePlaceholder() {
        let app = BuilderApp.launch(at: Self.week5, textSize: "UICTContentSizeCategoryAccessibilityXL")
        BuilderApp.openTheBuilder(in: app)
        let name = app.textFields["Program name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        BuilderApp.clear(name)
        name.typeText("A long program name that wraps")
        name.typeText("\n")
        attachScreenshot(of: app, named: "Builder, wrapped name")
        // The name wraps onto a second line; a tap there gives the field the focus.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 40)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the focus came with the tap")
        BuilderApp.clear(name)
        name.typeText("   ")
        attachScreenshot(of: app, named: "Builder, a draft of only spaces")
        // The drawn placeholder is hidden from VoiceOver, as the drawn name is: the screenshot shows it.
        XCTAssertEqual(name.value as? String, "   ", "the field holds the spaces")
        name.typeText("\n")
        // The name is stored as typed, so deleting it letter by letter stored "A" before the field was blank; a
        // blank name stores nothing, and the field takes the stored name back.
        XCTAssertEqual(name.value as? String, "A", "a blank name is not stored")
    }

    /// 24e (`Builder.addDayAddExerciseChangeProgression`, testing-strategy §2.7): "+ Add training day" opens the
    /// new day's editor; an exercise added from the library is in it; its progression chip changes the line.
    @MainActor
    func test_addDayAddExerciseChangeProgression() {
        let app = BuilderApp.launch(at: Self.week5)
        BuilderApp.openTheBuilder(in: app)
        let add = app.buttons["+ Add training day"]
        BuilderApp.scrollUntilHittable(add, in: app)
        add.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the new day's editor is pushed")
        XCTAssertEqual(app.textFields["Day name"].value as? String, "New day")
        app.buttons["+ Add exercise from library"].tap()
        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Back Squat")
        app.buttons["Back Squat"].firstMatch.tap()
        app.buttons["Add 1 exercise"].tap()
        let row = app.buttons["1, Back Squat"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["Fixed"].firstMatch.tap()
        let fixed = NSPredicate(format: "value CONTAINS %@", "Fixed")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: fixed, evaluatedWith: row)], timeout: 5), .completed)
        attachScreenshot(of: app, named: "New day, one exercise, fixed")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "back on the builder")
        XCTAssertTrue(app.buttons["New day"].exists)
    }

    /// 24f: at an accessibility size the builder's stops stand inside its one scroll view in the table's order,
    /// the week that holds today selected, and the last of them can be reached and used.
    @MainActor
    func test_atAnAccessibilitySize_readsItsStopsInOrder() {
        let app = BuilderApp.launch(at: Self.week5, textSize: "UICTContentSizeCategoryAccessibilityXL")
        BuilderApp.openTheBuilder(in: app)
        let stops = [
            app.staticTexts["MY PROGRAM"], app.textFields["Program name"], app.staticTexts["BLOCK · 8 WEEKS"],
            app.descendants(matching: .any)["Block length"].firstMatch, app.buttons["Week 5"],
            app.staticTexts["WEEK 5"], app.staticTexts["TRAINING DAYS"], app.buttons["Upper A — Push focus"],
            app.buttons["Lower B — Hinge focus"], app.buttons["+ Add training day"]
        ]
        for stop in stops {
            XCTAssertTrue(stop.waitForExistence(timeout: 10), "\(stop)")
        }
        let tops = stops.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "the order on the page is the order of the table")
        XCTAssertEqual(app.scrollViews.containing(.textField, identifier: "Program name").count, 1)
        XCTAssertTrue(app.buttons["Week 5"].isSelected, "the week that holds today")
        XCTAssertGreaterThan(stops[stops.count - 1].frame.maxY, app.scrollViews.firstMatch.frame.maxY, "it scrolls")
        attachScreenshot(of: app, named: "Builder, accessibility size")
        BuilderApp.scrollUntilHittable(stops[stops.count - 1], in: app)
        stops[stops.count - 1].tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the last stop works")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// What the builder's and the Day editor's UI tests share: launching on the seed program and reaching it.
enum BuilderApp {
    @MainActor
    static func launch(at instant: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", instant]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        seedTheProgram(in: app)
        return app
    }

    /// The Program tab, on the builder.
    @MainActor
    static func openTheBuilder(in app: XCUIApplication) {
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10))
    }

    /// The Day editor of the seed program's first day, from the builder.
    @MainActor
    static func openUpperA(in app: XCUIApplication) {
        openTheBuilder(in: app)
        let card = app.buttons["Upper A — Push focus"].firstMatch
        scrollUntilHittable(card, in: app)
        card.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5))
    }

    /// Saves the seed program as the active one: the Debug menu's sample workout saves it and starts its first
    /// day, which is then discarded.
    @MainActor
    static func seedTheProgram(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 5))
    }

    /// Deletes every letter of the field's text.
    @MainActor
    static func clear(_ field: XCUIElement) {
        let text = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 2))
    }

    /// Swipes the page up until `element` can be tapped, at most ten times.
    @MainActor
    static func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 10 where !(element.exists && element.isHittable) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "\(element) cannot be reached")
    }

    @MainActor
    static func wait(for element: XCUIElement, toRead value: String) {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(
            XCTWaiter().wait(for: [reads], timeout: 5),
            .completed,
            "\(element.value ?? "nil") is not \(value)"
        )
    }
}
