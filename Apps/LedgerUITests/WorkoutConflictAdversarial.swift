import XCTest

/// F10 S4 adversarial round 2 (G2), criteria 12 and 18: "You have a workout in progress" in the running app,
/// reached by the Debug menu's two sample rows. What `Smoke` does not ask: what the accessibility client is
/// given, that a tap outside cancels too, that after either way out the first workout is the one still
/// running with its time, and that after "Discard and start new" exactly one workout is left. Nightly only.
final class WorkoutConflictAdversarial: XCTestCase {
    private static let first = "debug.menu.startSampleWorkout"
    private static let other = "debug.menu.startOtherSampleWorkout"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_conflict_itsTree_bothWaysOut_andOneWorkoutAfterReplacing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        let minimize = app.buttons["workout.header.minimize"]
        let cancel = app.buttons["workout.conflict.cancel"].firstMatch

        ask(Self.first, in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        ask(Self.other, in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        try readTheDialog(in: app)
        // A tap well away from the dialog, wherever the system put it.
        let away = cancel.frame.midY < app.windows.firstMatch.frame.midY ? 0.9 : 0.12
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: away)).tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "a tap outside leaves the dialog")
        XCTAssertFalse(minimize.exists, "and shows nothing")
        let afterTapOutside = try theFirstWorkoutStillRuns(in: app, atLeast: 3)

        ask(Self.other, in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertFalse(minimize.exists, "Cancel shows nothing")
        _ = try theFirstWorkoutStillRuns(in: app, atLeast: afterTapOutside)

        try replaceAndCount(in: app)
    }

    /// The dialog as the accessibility client is given it: printed and kept, then its three buttons in
    /// reading order, each a button with its text, and the system's own way out.
    @MainActor
    private func readTheDialog(in app: XCUIApplication) throws {
        print("G2-TREE-BEGIN\n\(app.debugDescription)\nG2-TREE-END")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Workout in progress"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.staticTexts["You have a workout in progress"].exists)
        let buttons = ["resume", "replace", "cancel"].map { app.buttons["workout.conflict.\($0)"].firstMatch }
        XCTAssertEqual(buttons.map(\.label), ["Resume it", "Discard and start new", "Cancel"])
        XCTAssertEqual(buttons.map(\.isHittable), [true, true, true])
        XCTAssertEqual(buttons.map(\.isEnabled), [true, true, true])
        let tops = buttons.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "Cancel is read last")
        XCTAssertTrue(buttons.allSatisfy { $0.frame.height >= 44 }, "44 point targets: \(buttons.map(\.frame.height))")
        XCTAssertTrue(app.otherElements["PopoverDismissRegion"].exists, "the system's own way out")
        XCTAssertFalse(app.buttons["workout.header.minimize"].exists, "no cover is under the dialog")
    }

    /// Asks for the first day: its workout is shown, with no dialog, as "Upper A", having run at least
    /// `seconds`. Then minimizes it. Answers the seconds it read.
    @MainActor
    private func theFirstWorkoutStillRuns(in app: XCUIApplication, atLeast seconds: Int) throws -> Int {
        ask(Self.first, in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the first day's workout is still the live one")
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, "Upper A — Push focus")
        let ran = try elapsedSeconds(in: app)
        XCTAssertGreaterThanOrEqual(ran, seconds, "the same workout, still counting")
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        return ran
    }

    /// "Discard and start new", then: the other day's workout is the one live (its row shows it with no
    /// dialog), and the first day's is gone (its row now raises the dialog, and "Resume it" shows the other).
    @MainActor
    private func replaceAndCount(in app: XCUIApplication) throws {
        let minimize = app.buttons["workout.header.minimize"]
        let title = app.staticTexts["workout.header.title"]
        let resume = app.buttons["workout.conflict.resume"].firstMatch
        ask(Self.other, in: app)
        let replace = app.buttons["workout.conflict.replace"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 10))
        replace.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lower A — Squat focus")
        XCTAssertLessThanOrEqual(try elapsedSeconds(in: app), 3, "newly started")
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        ask(Self.other, in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the other day's workout is live: no dialog")
        XCTAssertFalse(resume.exists)
        XCTAssertEqual(title.label, "Lower A — Squat focus")
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        ask(Self.first, in: app)
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "the first day's workout is gone: its day now conflicts")
        resume.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lower A — Squat focus", "one workout is left")
    }

    @MainActor
    private func elapsedSeconds(in app: XCUIApplication) throws -> Int {
        let drawn = app.otherElements["workout.header.elapsed"].staticTexts.firstMatch.label
        let parts = try drawn.split(separator: ":").map { try XCTUnwrap(Int($0), "not a time: \(drawn)") }
        XCTAssertTrue((2 ... 3).contains(parts.count), "not a time: \(drawn)")
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Opens the Debug menu from Today's title and taps one of its sample rows.
    @MainActor
    private func ask(_ row: String, in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let button = app.buttons[row]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
}
