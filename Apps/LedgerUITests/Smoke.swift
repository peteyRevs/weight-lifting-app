import XCTest

/// Selected by the `PR` test plan as `LedgerUITests/Smoke` (docs/testing-strategy.md §8). F07 criterion 1 and F08
/// criteria 12 and 14: the app launches on a fresh database (`-LEDGER_UITEST`) to onboarding, full screen, and
/// "Skip setup" lands on Today, with the tabs. The other tests launch with the seed program
/// (`-LEDGER_UITEST_PROGRAM seed`, F08) and open on Today. F10 S4 criterion 10: the workout's cover in the
/// running app, and criterion 18: the conflict with a workout that is running; both reached through the Debug
/// menu's sample rows until Today starts workouts (F09). F10 S7a: a workout is saved and Today shows it logged.
final class Smoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_freshInstall_skipsSetupToToday() {
        let app = XCUIApplication.fresh()
        app.launch()
        let onboarding = app.staticTexts["onboarding.title"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10))
        XCTAssertEqual(onboarding.label, "What are you training for?")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "onboarding is full screen: no tab bar")
        XCTAssertFalse(app.staticTexts["today.title"].exists)

        XCTAssertTrue(app.skipSetupToToday())
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(onboarding.exists)
    }

    /// The sample workout starts and its cover goes up over the tabs with no more than a second or two on
    /// its clock; the time then reads later; Minimize takes the cover down and leaves the workout running;
    /// asking for the same day again shows that workout; Finish, then Discard, ends it and takes the cover
    /// down. The time is read from the text the system's timer draws, in seconds. That a start reads
    /// exactly "0:00", and an hour "1:01:05", is a reference's to show (`WorkoutSnapshotTests`): by the time
    /// a UI test can read the cover, its first second may have passed.
    @MainActor
    func test_sampleWorkout_startsCountsMinimizesResumesDiscards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        startSampleWorkout(in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        let atStart = try elapsedSeconds(in: app)
        XCTAssertLessThanOrEqual(atStart, 2, "a workout just started")
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, "Upper A — Push focus")
        XCTAssertEqual(app.otherElements["workout.header.progress"].value as? String, "Exercise 1 of 5")
        XCTAssertFalse(today.isHittable, "the cover is over the tabs")
        XCTAssertEqual(app.otherElements["workout.header.elapsed"].label, "Elapsed time")
        attachScreenshot(of: app, named: "Workout, just started")
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in (try? elapsedSeconds(in: app)).map { $0 > atStart } ?? false },
            object: nil
        )
        wait(for: [counted], timeout: 10)

        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        XCTAssertTrue(becomesHittable(today), "the tabs are back")

        startSampleWorkout(in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the same day again shows the workout that is running")
        XCTAssertGreaterThan(try elapsedSeconds(in: app), atStart, "it kept counting while it was minimized")
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["End workout?"].exists)
        XCTAssertTrue(app.buttons["workout.finish.keep"].firstMatch.exists)
        attachScreenshot(of: app, named: "End workout?")
        discard.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        XCTAssertTrue(becomesHittable(today), "the tabs are back")
    }

    /// F10 S4 criterion 18: with the first day's sample workout running, asking for another day's raises
    /// "You have a workout in progress" with its three choices drawn, and each does what it says: "Cancel"
    /// shows nothing and changes nothing; "Resume it" shows the workout that was running; "Discard and
    /// start new" shows the other day's workout, newly started.
    @MainActor
    func test_sampleWorkout_anotherDay_cancelResumeAndReplace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        let minimize = app.buttons["workout.header.minimize"]
        let title = app.staticTexts["workout.header.title"]
        let choices = ["resume", "replace", "cancel"].map { app.buttons["workout.conflict.\($0)"].firstMatch }

        startSampleWorkout(in: app)
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        startSampleWorkout(in: app, row: "debug.menu.startOtherSampleWorkout")
        XCTAssertTrue(choices[2].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You have a workout in progress"].exists)
        XCTAssertEqual(choices.map(\.label), ["Resume it", "Discard and start new", "Cancel"])
        XCTAssertEqual(choices.map(\.isHittable), [true, true, true], "all three are drawn")
        attachScreenshot(of: app, named: "Workout in progress")
        choices[2].tap()
        XCTAssertTrue(choices[2].waitForNonExistence(timeout: 5))
        XCTAssertTrue(becomesHittable(today), "Cancel shows nothing")
        XCTAssertFalse(minimize.exists)

        startSampleWorkout(in: app, row: "debug.menu.startOtherSampleWorkout")
        XCTAssertTrue(choices[0].waitForExistence(timeout: 10), "Cancel discarded nothing: it asks again")
        choices[0].tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Upper A — Push focus", "Resume it shows the workout that was running")
        let ran = try elapsedSeconds(in: app)
        XCTAssertGreaterThan(ran, 5, "with the time it has run")
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        startSampleWorkout(in: app, row: "debug.menu.startOtherSampleWorkout")
        XCTAssertTrue(choices[1].waitForExistence(timeout: 10))
        choices[1].tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lower A — Squat focus", "Discard and start new shows the other day's workout")
        XCTAssertLessThan(try elapsedSeconds(in: app), ran, "newly started")
    }

    /// The seconds the cover's elapsed time reads now: the text the system's timer draws inside the
    /// element VoiceOver knows as "Elapsed time" ("0:07", "1:01:05").
    @MainActor
    private func elapsedSeconds(in app: XCUIApplication) throws -> Int {
        let drawn = app.otherElements["workout.header.elapsed"].staticTexts.firstMatch.label
        let parts = try drawn.split(separator: ":").map { try XCTUnwrap(Int($0), "not a time: \(drawn)") }
        XCTAssertTrue((2 ... 3).contains(parts.count), "not a time: \(drawn)")
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Whether `element` can be tapped within a few seconds: it exists under the cover all along, so only
    /// this says that the cover is down.
    @MainActor
    private func becomesHittable(_ element: XCUIElement) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [hittable], timeout: 5) == .completed
    }

    /// Opens the Debug menu from Today's title and taps one of its sample rows: the first day's, or the
    /// other day's.
    @MainActor
    private func startSampleWorkout(in app: XCUIApplication, row identifier: String = "debug.menu.startSampleWorkout") {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons[identifier]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
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

extension Smoke {
    /// F10 S7a: the sample workout with one set logged is saved. "Finish" opens "End workout?" with what
    /// the workout holds; "Save workout" stores it and takes the cover down onto Today, which shows the
    /// session as logged, with the one set, and offers no workout to resume.
    ///
    /// The app's clock is moved to the Monday of the seed program's first week: the sample workout is
    /// that day's session, so Today has a Logged card for it. Under a moved clock the cover's elapsed
    /// time is not read.
    @MainActor
    func test_sampleWorkout_logASet_saveWorkout_todayShowsItLogged() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        startSampleWorkout(in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        let save = app.buttons["workout.finish.save"].firstMatch
        let summary = app.staticTexts["workout.finish.summary"].firstMatch

        // With nothing logged the sheet offers no save.
        app.buttons["workout.header.finish"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "nothing is logged yet")
        XCTAssertTrue(summary.label.hasPrefix("0 of "), summary.label)
        app.buttons["workout.finish.keep"].firstMatch.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))

        app.buttons["Log set 1"].tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        app.buttons["workout.header.finish"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["End workout?"].exists)
        XCTAssertTrue(summary.label.hasPrefix("1 of "), summary.label)
        XCTAssertTrue(summary.label.hasSuffix(" lb moved"), summary.label)
        XCTAssertTrue(save.isEnabled)
        attachScreenshot(of: app, named: "End workout? with a set logged")

        save.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 10), "the cover is down")
        XCTAssertTrue(becomesHittable(today), "the tabs are back")
        XCTAssertTrue(app.buttons["View session"].waitForExistence(timeout: 5), "Today shows the session as logged")
        XCTAssertTrue(app.staticTexts["LOGGED · WEEK 1"].exists)
        XCTAssertFalse(app.buttons["Resume workout"].exists, "nothing is live")
        attachScreenshot(of: app, named: "Today, the saved workout logged")
    }
}
