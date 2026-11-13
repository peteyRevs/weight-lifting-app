import XCTest

/// F15 S1, criteria 3–5: the critical flows, each chained in one launch, through the screens a lifter uses and never
/// the Debug menu (question 4, A). This file is criterion 3, the M1 exit's own wording: a new user onboards, runs a
/// full workout with a superset round and a swap, finishes, and finds it in History and on the exercise's chart.
/// `Flows+Program` and `Flows+Units` are criteria 4 and 5. Nightly only: the `PR` plan selects `Smoke`.
///
/// Every step is one of `Steps`, or reads the thing it names; a screenshot is kept at each stage (risk R5). The flow
/// targets 4 minutes on a Mac, inside the nightly plan's 600 s a test (C12).
final class Flows: XCTestCase {
    /// Monday of a week: onboarding's default program (4 days, "Both, honestly") starts the week that holds it and
    /// trains Upper A on Mondays (`ProgramTemplates.upperLower`). Noon UTC is Monday in every zone from UTC−11 to
    /// UTC+11. If onboarding's week ever changes, the test fails at Today's first card, saying so (risk R8).
    static let monday = "2026-09-14T12:00:00Z"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_fullWorkoutToHistory() throws {
        let steps = Steps(launching: ["-LEDGER_UITEST_NOW", Self.monday], for: self)
        onboardWithTheDefaults(steps)
        XCTAssertEqual(steps.todayTitle.label, "Upper A", "Monday is the default program's Upper A (R8)")
        XCTAssertTrue(steps.app.staticTexts["Upper A — Push focus"].exists, "Today's card names the day")
        steps.attachScreenshot(named: "Today, Upper A up next")

        steps.startFromToday()
        XCTAssertTrue(steps.reads(steps.cardTitle, "Barbell Bench Press"))
        // Each set's rest is skipped before the next set, so each rest proven is that set's own.
        for set in 1 ... 3 {
            steps.logSet("\(set)")
            XCTAssertTrue(steps.skip.waitForExistence(timeout: 5), "set \(set) starts a rest")
            if set < 3 {
                steps.skipRest()
            }
        }
        steps.attachScreenshot(named: "Three sets of the bench press, resting")
        steps.skipRest()

        let swapped = try swapAndLogTheSecondExercise(steps)
        logTheSupersetsFirstRound(steps)

        steps.finishAndSave()
        expectTheReceipt(listing: swapped, steps)
        steps.closeReceipt()
        XCTAssertTrue(steps.app.buttons["View session"].waitForExistence(timeout: 5), "Today shows it logged")
        XCTAssertFalse(steps.app.buttons["Resume workout"].exists, "nothing is live")

        findInHistory(swapped, steps)
        findOnTheChart("Barbell Bench Press", steps)
    }

    /// Onboarding's three steps with what each picks first, then "Start training": Today, with the tabs.
    @MainActor
    private func onboardWithTheDefaults(_ steps: Steps) {
        let app = steps.app
        let title = app.staticTexts["onboarding.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "a fresh install opens on onboarding")
        for next in ["How many days a week?", "Your program"] {
            app.buttons["onboarding.cta"].tap()
            XCTAssertTrue(steps.reads(title, next), "\(title.label) is not \(next)")
        }
        XCTAssertEqual(app.buttons["onboarding.cta"].label, "Start training")
        app.buttons["onboarding.cta"].tap()
        XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10), "Start training lands on Today")
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
    }

    /// The second exercise, jumped to from "REMAINING": swapped before any of its sets is logged (a swap is offered
    /// only then, F10 S8 ruling Q2) for the sheet's first row, given a set more with "+ Add set", and one set
    /// logged. Returns the replacement's name.
    @MainActor
    private func swapAndLogTheSecondExercise(_ steps: Steps) throws -> String {
        let app = steps.app
        app.buttons["workout.remaining.row.1"].tap()
        XCTAssertTrue(steps.reads(steps.cardTitle, "Incline DB Press"), "the jump shows the second exercise")
        app.buttons["workout.card.swap"].tap()
        let row = app.buttons["workout.swap.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the swap sheet's rows are read")
        let name = try XCTUnwrap(row.label.components(separatedBy: ", ").first)
        steps.attachScreenshot(named: "Swap sheet")
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the sheet goes down")
        XCTAssertTrue(steps.reads(steps.cardTitle, name), "the card reads the replacement's name")

        app.buttons["workout.card.addSet"].tap()
        XCTAssertTrue(app.buttons["Log set 4"].waitForExistence(timeout: 5), "+ Add set appends a fourth row")
        steps.logSet("1")
        XCTAssertFalse(app.buttons["workout.card.swap"].exists, "with a set logged it is offered no swap")
        steps.skipRest()
        return name
    }

    /// The superset, jumped to from "REMAINING", as `WorkoutSuperset` reads it: A1 logged starts no rest, B1 logged
    /// starts the group's rest, which is skipped.
    @MainActor
    private func logTheSupersetsFirstRound(_ steps: Steps) {
        let app = steps.app
        app.buttons["workout.remaining.row.3"].tap()
        let block = app.staticTexts["workout.block.title"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "the superset is drawn as one block")
        XCTAssertTrue(steps.reads(block, "Round 1 of 3"))
        steps.logSet("A1")
        XCTAssertFalse(steps.skip.waitForExistence(timeout: 2), "a member that ends no round starts no rest")
        steps.logSet("B1")
        XCTAssertTrue(steps.skip.waitForExistence(timeout: 5), "the round's last member starts the group's rest")
        steps.attachScreenshot(named: "Superset, the group's rest")
        steps.skipRest()
        XCTAssertTrue(steps.reads(block, "Round 2 of 3"))
    }

    /// The receipt: its volume tile in pounds, and a row for each exercise logged, the replacement's among them.
    @MainActor
    private func expectTheReceipt(listing swapped: String, _ steps: Steps) {
        // The receipt's tile reads "6,282 lb moved" exactly; Today's tile under the cover reads otherwise.
        let moved = NSPredicate(format: "label MATCHES %@", "^[0-9,]+ lb moved$")
        XCTAssertTrue(steps.app.descendants(matching: .any).matching(moved).firstMatch.exists, "the volume tile")
        XCTAssertTrue(steps.app.staticTexts["LB MOVED"].exists, "the volume tile's caption")
        let logged = steps.app.buttons.matching(NSPredicate(format: "label CONTAINS ', Logged '"))
        XCTAssertEqual(logged.count, 4, "the bench press, the replacement and the superset's two members")
        XCTAssertTrue(steps.element(startingWith: "\(swapped), ").exists, "the receipt lists the replacement")
        steps.attachScreenshot(named: "The receipt")
    }

    /// The History tab lists the workout; its detail lists the replacement.
    @MainActor
    private func findInHistory(_ swapped: String, _ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "History lists the workout")
        XCTAssertTrue(row.label.hasPrefix("Upper A"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "its detail")
        XCTAssertTrue(steps.element(startingWith: "\(swapped), ").exists, "the detail lists the replacement")
        steps.attachScreenshot(named: "History, the workout's detail")
    }

    /// Library, then `exercise` in RECENTLY LOGGED, opens its history: the chart is drawn, with this week's point,
    /// where an exercise with no session reads "Log a session to start the chart."; SESSION LOG lists the session.
    @MainActor
    private func findOnTheChart(_ exercise: String, _ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["Library"].tap()
        let recent = NSPredicate(format: "label == %@ AND value CONTAINS '1 session'", exercise)
        let row = app.buttons.matching(recent).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(exercise) is in RECENTLY LOGGED")
        row.tap()
        XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["Estimated 1RM by week"].waitForExistence(timeout: 5), "the chart is drawn")
        XCTAssertFalse(app.staticTexts["Log a session to start the chart."].exists, "it has a point")
        XCTAssertTrue(app.staticTexts["SESSION LOG"].exists)
        let sessions = app.buttons.matching(NSPredicate(format: "value CONTAINS '×'"))
        XCTAssertEqual(sessions.count, 1, "the session logged today")
        steps.attachScreenshot(named: "The exercise's history and chart")
    }
}
