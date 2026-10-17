import XCTest

/// F10 S5, criterion 1: the workout's page in the running app, inside its real scroll view, which no hosted
/// test can read (docs/testing-strategy.md §2.6). The sample workout from the Debug menu is logged set by
/// set: the steppers, the check and its undo, "+ Add set", the engine moving on to the next exercise, and a
/// jump from "REMAINING"; then the page's stops are read in order at an accessibility text size. Nightly
/// only, as every UI test but `Smoke` is.
///
/// The sample is the seed program's Upper A on a fresh database, so no exercise has a last workout: the
/// card reads "No history yet" and draws no "Repeat". "Repeat" is the store's and the references' to show.
final class WorkoutLogging: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_sampleWorkout_stepsLogsUndoesAddsAndJumps() throws {
        let app = launch()
        startSampleWorkout(in: app)
        let title = app.staticTexts["workout.card.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Barbell Bench Press")
        XCTAssertTrue(app.staticTexts["Exercise 1 of 5"].exists)
        XCTAssertTrue(app.staticTexts["Last, No history yet"].exists)
        XCTAssertFalse(app.buttons["workout.card.repeat"].exists, "no last workout, no Repeat")
        XCTAssertTrue(app.staticTexts["REMAINING"].exists)
        attachScreenshot(of: app, named: "Workout page, just started")

        try stepAndLogTheFirstSet(in: app)
        attachScreenshot(of: app, named: "Workout page, one set logged")
        undoAndLogAgain(in: app)
        // A logged set starts a rest, whose panel floats over the page's end (F10 S6; `WorkoutRest` tests
        // it). This test is of the page: it skips each rest, so that no control it taps is under the panel.
        skipRest(in: app)

        // "+ Add set" appends a sixth row; logging every row moves the card to the next exercise.
        app.buttons["workout.card.addSet"].tap()
        XCTAssertTrue(app.buttons["Log set 6"].waitForExistence(timeout: 5))
        for set in 2 ... 5 {
            app.buttons["Log set \(set)"].tap()
            XCTAssertTrue(app.buttons["Undo set \(set)"].waitForExistence(timeout: 5), "set \(set)")
            skipRest(in: app)
        }
        // The last row logged, nothing of the bench press is left: the engine's cursor is on the next exercise.
        app.buttons["Log set 6"].tap()
        wait(for: title, toBe: "Incline DB Press")
        skipRest(in: app)
        XCTAssertTrue(title.isHittable, "the next exercise's name is on screen")
        XCTAssertEqual(app.otherElements["workout.header.progress"].value as? String, "Exercise 2 of 5")
        XCTAssertTrue(app.staticTexts["Exercise 2 of 5"].exists)

        // A row of "REMAINING" jumps to its exercise, whose name is on screen.
        app.buttons["workout.remaining.row.3"].tap()
        wait(for: title, toBe: "Lat Pulldown")
        XCTAssertTrue(title.isHittable, "the name of the exercise jumped to is on screen")
        XCTAssertEqual(app.otherElements["workout.header.progress"].value as? String, "Exercise 4 of 5")
        XCTAssertTrue(app.buttons["Log set 1"].exists)
        attachScreenshot(of: app, named: "Workout page, after a jump")

        discard(in: app)
    }

    /// The steppers change the shown row: two taps on "+" are two steps of 5 lb, one on "−" one rep. The
    /// check then logs the row as it reads; the row is drawn done, and the next row is the shown one, with
    /// the weight and reps it had.
    @MainActor
    private func stepAndLogTheFirstSet(in app: XCUIApplication) throws {
        let weight = stop("5 LB", in: app)
        let reps = stop("1 REP", in: app)
        let startWeight = try number(in: weight)
        let startReps = try number(in: reps)
        tap(weight, at: 0.9)
        tap(weight, at: 0.9)
        wait(for: weight, toRead: "\(startWeight + 10) pounds")
        tap(reps, at: 0.1)
        wait(for: reps, toRead: "\(startReps - 1) reps")

        app.buttons["Log set 1"].tap()
        let undo = app.buttons["Undo set 1"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isSelected)
        let logged = app.buttons["Set 1, \(startWeight + 10) pounds, \(startReps - 1) reps"]
        XCTAssertTrue(logged.exists)
        XCTAssertEqual(logged.value as? String, "Done")
        let next = app.buttons["Set 2, \(startWeight) pounds, \(startReps) reps"]
        XCTAssertEqual(next.value as? String, "Current set")
        wait(for: weight, toRead: "\(startWeight) pounds")
    }

    /// A logged row's check un-logs it; logging it again logs it. In the first second after a set is logged
    /// its check ignores an un-log (a second touch must not take the set back), so the undo is tapped once
    /// more if the first tap came inside that second.
    @MainActor
    private func undoAndLogAgain(in app: XCUIApplication) {
        let undo = app.buttons["Undo set 1"]
        undo.tap()
        if !app.buttons["Log set 1"].waitForExistence(timeout: 2) {
            undo.tap()
        }
        XCTAssertTrue(app.buttons["Log set 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)
        app.buttons["Log set 1"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
    }

    /// The backstop of the hosted trees: at an accessibility text size the page's stops stand in the real
    /// scroll view in the table's order, top to bottom, with their states, and a control that is off screen
    /// can still be reached and used.
    @MainActor
    func test_sampleWorkout_atAnAccessibilitySize_readsItsStopsInOrder() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        // Today's own page is a scroll view, and it is still counted under the cover: the cover adds one.
        let underTheCover = app.scrollViews.count
        startSampleWorkout(in: app)
        XCTAssertTrue(app.staticTexts["workout.card.title"].waitForExistence(timeout: 10))
        let pages = app.scrollViews.containing(.staticText, identifier: "workout.card.title")
        XCTAssertEqual(pages.count, 1, "the page is one scroll view under the header")
        XCTAssertEqual(app.scrollViews.count, underTheCover + 1, "and the cover holds no other")
        attachScreenshot(of: app, named: "Workout page, accessibility size")

        let stops = pageStops(in: app)
        for element in stops {
            XCTAssertTrue(element.exists, "\(element)")
        }
        let tops = stops.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "the order on the page is the order of the table")
        let scroll = pages.firstMatch.frame
        XCTAssertGreaterThan(stops[stops.count - 1].frame.maxY, scroll.maxY, "the page is longer than the screen")
        XCTAssertGreaterThanOrEqual(stops[0].frame.minY, scroll.minY, "the page starts under the header")
        XCTAssertLessThanOrEqual(app.buttons["workout.header.finish"].frame.maxY, scroll.minY, "the header is pinned")

        let first = app.buttons["Log set 1"]
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(first.isSelected)
        XCTAssertEqual(stops[4].value as? String, "Current set")
        XCTAssertEqual(stops[7].value as? String, "Pending")
        first.tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo set 1"].isSelected)
        XCTAssertEqual(stops[7].value as? String, "Current set")
        skipRest(in: app)

        // The last exercise's row is off screen: tapping it scrolls to it and jumps.
        app.buttons["workout.remaining.row.4"].tap()
        wait(for: app.staticTexts["workout.card.title"], toBe: "Cable Lateral Raise")
        XCTAssertTrue(app.staticTexts["workout.card.title"].isHittable, "the page stands at its top after the jump")
        XCTAssertTrue(app.staticTexts["Exercise 5 of 5"].isHittable)
        XCTAssertFalse(app.staticTexts["REMAINING"].exists, "nothing remains after the last exercise")
        XCTAssertTrue(app.buttons["workout.header.minimize"].isHittable, "the header stayed where it was")
        attachScreenshot(of: app, named: "Workout page, accessibility size, last exercise")

        discard(in: app)
    }

    /// The page's stops, in the order of the notes' table: the place, the name, the two facts, the first
    /// row with its steppers, the second and the fifth rows, "+ Add set", "REMAINING" and its first and
    /// last rows.
    @MainActor
    private func pageStops(in app: XCUIApplication) -> [XCUIElement] {
        func row(_ number: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Set \(number), ")).firstMatch
        }
        return [
            app.staticTexts["Exercise 1 of 5"], app.staticTexts["workout.card.title"],
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'TARGET, '")).firstMatch,
            app.staticTexts["Last, No history yet"],
            row(1), stop("5 LB", in: app), stop("1 REP", in: app), row(2), row(5),
            app.buttons["workout.card.addSet"], app.staticTexts["REMAINING"],
            app.buttons["workout.remaining.row.1"], app.buttons["workout.remaining.row.4"]
        ]
    }
}

private extension WorkoutLogging {
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

    /// "Skip rest" on the rest panel a logged set brought up; the panel goes.
    @MainActor
    private func skipRest(in app: XCUIApplication) {
        let skip = app.buttons["workout.rest.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "a logged set starts a rest")
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
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

    /// A stepper, which VoiceOver knows as one adjustable stop named by its step ("5 LB", "1 REP").
    @MainActor
    private func stop(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Taps a stepper at `share` of its width: its "−" is at its leading end and its "+" at its trailing end.
    @MainActor
    private func tap(_ stepper: XCUIElement, at share: CGFloat) {
        stepper.coordinate(withNormalizedOffset: CGVector(dx: share, dy: 0.5)).tap()
    }

    /// The whole number a stepper's value starts with: 185 of "185 pounds", 5 of "5 reps".
    @MainActor
    private func number(in stepper: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(stepper.value as? String, "the stepper has no value")
        return try XCTUnwrap(value.split(separator: " ").first.flatMap { Int($0) }, "not a whole number: \(value)")
    }

    @MainActor
    private func wait(for stepper: XCUIElement, toRead value: String) {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: stepper)
        XCTAssertEqual(
            XCTWaiter().wait(for: [reads], timeout: 5),
            .completed,
            "\(stepper.value ?? "nil") is not \(value)"
        )
    }

    @MainActor
    private func wait(for text: XCUIElement, toBe label: String) {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: text)
        XCTAssertEqual(XCTWaiter().wait(for: [reads], timeout: 5), .completed, "\(text.label) is not \(label)")
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
