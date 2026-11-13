import XCTest

/// F15 S1, criterion 4 as question 2 restates it (A): an edit of the day in the Day editor reaches Today's card in the
/// same launch. Today follows the program as it is stored (`observe`); every UI-test launch is a fresh database, so
/// the brief's relaunch on a later date would see none of the edit, and a relaunch is pinned hosted
/// (`WorkoutRelaunchTests`).
///
/// On the seed program at noon on Wednesday of its week 5, Today's session is Lower A (`Today` says why).
extension Flows {
    static let wednesday = "2026-09-16T12:00:00Z"

    @MainActor
    func test_programEditReflectsOnToday() {
        let arguments = ["-LEDGER_UITEST_NOW", Self.wednesday, "-LEDGER_UITEST_PROGRAM", "seed"]
        let steps = Steps(launching: arguments, for: self)
        XCTAssertTrue(steps.app.buttons["Start workout"].waitForExistence(timeout: 10), "a session day")
        XCTAssertEqual(steps.todayTitle.label, "Lower A")
        let squat = steps.element(startingWith: "Back Squat, ")
        let deadlift = steps.element(startingWith: "Romanian Deadlift, ")
        let row = steps.element(startingWith: "Barbell Row, ")
        XCTAssertTrue(squat.exists, "Today's card shows the day's first exercise")
        XCTAssertFalse(row.exists, "control: the exercise to add is not on the card")

        openLowerA(steps)
        addFromTheLibrary("Barbell Row", steps)
        backToToday(steps)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the added exercise is on Today's card")
        XCTAssertTrue(squat.exists)
        steps.attachScreenshot(named: "Today, an exercise added")

        openLowerA(steps)
        let first = steps.app.buttons["1, Back Squat"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let remove = steps.app.buttons["Remove"].firstMatch
        steps.scrollUntilHittable(remove)
        remove.tap()
        XCTAssertTrue(steps.app.buttons["1, Romanian Deadlift"].firstMatch.waitForExistence(timeout: 5))
        backToToday(steps)
        XCTAssertTrue(squat.waitForNonExistence(timeout: 10), "the removed exercise left Today's card")
        XCTAssertTrue(deadlift.exists, "the card names the next one")
        let legPress = steps.element(startingWith: "Leg Press, ")
        XCTAssertLessThan(deadlift.frame.minY, legPress.frame.minY, "first, above the rest of the day")
        steps.attachScreenshot(named: "Today, the first exercise removed")
    }

    /// The Program tab, then Lower A's card in the builder: its Day editor.
    @MainActor
    private func openLowerA(_ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10), "the builder")
        let card = app.buttons["Lower A — Squat focus"].firstMatch
        steps.scrollUntilHittable(card)
        card.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the Day editor")
    }

    /// "+ Add exercise from library", the query `exercise`, its row picked, and "Add 1 exercise": the day's last row.
    @MainActor
    private func addFromTheLibrary(_ exercise: String, _ steps: Steps) {
        let app = steps.app
        let open = app.buttons["+ Add exercise from library"]
        steps.scrollUntilHittable(open)
        open.tap()
        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the library sheet")
        search.tap()
        search.typeText(exercise)
        let hit = app.buttons[exercise].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "\(exercise) is found")
        hit.tap()
        app.buttons["Add 1 exercise"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "the sheet closed")
        // Lower A's rows are 1, 2, 3A and 3B (its last two are a superset): the added exercise is the fourth.
        XCTAssertTrue(app.buttons["4, \(exercise)"].firstMatch.exists, "\(exercise) is the day's last row")
    }

    /// The Day editor's own "Program", not the tab bar's, back to the builder; then the Today tab.
    @MainActor
    private func backToToday(_ steps: Steps) {
        let app = steps.app
        let bar = app.tabBars.firstMatch.frame
        let backs = app.buttons.matching(NSPredicate(format: "label == 'Program'")).allElementsBoundByIndex
        let back = backs.first { !bar.intersects($0.frame) } ?? app.buttons["Program"].firstMatch
        back.tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 5), "back on the builder")
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(steps.becomesHittable(steps.todayTitle), "on Today")
    }
}
