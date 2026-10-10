import XCTest

/// F09 S5 criterion 11, on screen: Today in the running app, on a program. Nightly only: the `PR` plan selects
/// `Smoke`.
///
/// **The date is the test's own.** Which card Today shows depends on the day, so each test launches with
/// `-LEDGER_UITEST_NOW`, which moves the app's clock to an instant in week 5 of the spec's seed program (8
/// weeks from Monday 2026-08-17: Upper A on Monday, Lower A on Wednesday, Upper B on Friday, Lower B on
/// Saturday). The instants are noon UTC, the same calendar day in every time zone from UTC−11 to UTC+11.
///
/// **The program is the Debug menu's.** A UI test's database holds the catalog and no program, so each test
/// first starts the menu's sample workout, which saves the seed program, and discards that workout. Under a
/// moved clock the cover's elapsed time is not read: the system's timer counts it from the device's clock.
final class Today: XCTestCase {
    /// Thursday of week 5: nothing is scheduled.
    private static let restDay = "2026-09-17T12:00:00Z"
    /// Wednesday of week 5: Lower A.
    private static let sessionDay = "2026-09-16T12:00:00Z"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A rest day: "Train off-schedule" opens the sheet with the program's four days; Cancel closes it and
    /// starts nothing; a day picked there closes it and opens that day's workout over the tabs; minimized,
    /// Today offers Resume, which opens the same workout again.
    @MainActor
    func test_restDay_offScheduleSheet_cancelsAndPicksADay() {
        let app = launch(at: Self.restDay)
        let title = app.staticTexts["today.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Today", "no program yet")
        XCTAssertTrue(app.staticTexts["No program yet"].exists)
        seedTheProgram(in: app)

        XCTAssertTrue(app.staticTexts["No session today"].waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Rest day")
        XCTAssertTrue(app.staticTexts["Thursday, September 17"].exists)
        XCTAssertTrue(app.staticTexts["Nothing scheduled for Thursday in week 5. Next up is Friday."].exists)
        attachScreenshot(of: app, named: "Today, rest day")

        let offSchedule = app.buttons["Train off-schedule"]
        let cancel = app.buttons["Cancel"]
        let minimize = app.buttons["workout.header.minimize"]
        let rows = ["Upper A", "Lower A", "Upper B", "Lower B"].map { day in
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(day) — ")).firstMatch
        }

        offSchedule.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pick a day from week 5."].exists)
        XCTAssertEqual(rows.map(\.exists), [true, true, true, true], "the program's four days")
        attachScreenshot(of: app, named: "Off-schedule sheet")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(becomesHittable(offSchedule), "Today is back")
        XCTAssertFalse(minimize.exists, "Cancel started nothing")

        offSchedule.tap()
        XCTAssertTrue(rows[3].waitForExistence(timeout: 5))
        rows[3].tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "the picked day's workout is over the tabs")
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, "Lower B — Hinge focus")
        XCTAssertFalse(cancel.exists, "the sheet is gone")

        minimizeAndResume(in: app, workout: "Lower B — Hinge focus") {
            XCTAssertEqual(title.label, "Rest day", "the title is the calendar's")
            attachScreenshot(of: app, named: "Today, resume on a rest day")
        }

        discardTheWorkout(in: app)
        XCTAssertTrue(becomesHittable(offSchedule), "discarded, the rest day's card is back")
        XCTAssertFalse(app.buttons["Resume workout"].exists)
    }

    /// A session day: the card is the day's, "Start workout" opens its workout over the tabs, and Today
    /// offers Resume once it is minimized. The gear opens the Settings placeholder on Today's stack.
    @MainActor
    func test_sessionDay_startWorkoutOpensTheCover() {
        let app = launch(at: Self.sessionDay)
        let title = app.staticTexts["today.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        seedTheProgram(in: app)

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lower A")
        XCTAssertTrue(app.staticTexts["Wednesday, September 16"].exists)
        XCTAssertTrue(app.staticTexts["Lower A — Squat focus"].exists)
        attachScreenshot(of: app, named: "Today, up next")

        app.buttons["Settings"].tap()
        let settings = app.staticTexts["settings.title"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))

        start.tap()
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, "Lower A — Squat focus")
        XCTAssertEqual(app.otherElements["workout.header.progress"].value as? String, "Exercise 1 of 4")
        minimizeAndResume(in: app, workout: "Lower A — Squat focus") {
            XCTAssertFalse(start.exists)
        }
        discardTheWorkout(in: app)
        XCTAssertTrue(becomesHittable(start), "discarded, Start workout is back")
    }

    /// At an accessibility text size the page is longer than the screen: its stops keep their order down the
    /// real scroll view, and the button at the card's end is reached and starts the workout.
    @MainActor
    func test_sessionDay_atAnAccessibilitySize_readsInOrderAndStarts() {
        let app = launch(at: Self.sessionDay, textSize: "UICTContentSizeCategoryAccessibilityXL")
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        seedTheProgram(in: app)

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        // The first of each: the date is found twice, in the header and as the week strip's day of today.
        let stops = [
            app.staticTexts["Wednesday, September 16"],
            app.staticTexts["today.title"],
            app.staticTexts["UP NEXT"],
            app.staticTexts["Lower A — Squat focus"],
            start,
            app.staticTexts["RECENT"]
        ].map(\.firstMatch)
        XCTAssertEqual(stops.map(\.exists), stops.map { _ in true })
        let tops = stops.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "down the page in the tree's order")
        XCTAssertGreaterThan(stops[5].frame.maxY, app.frame.maxY, "the page is longer than the screen")
        attachScreenshot(of: app, named: "Today, accessibility size")

        start.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
    }

    /// Minimizes the cover that is up; Today then offers Resume on a card that is the workout's, where `check`
    /// looks at it; Resume opens the same workout again.
    @MainActor
    private func minimizeAndResume(in app: XCUIApplication, workout name: String, check: () -> Void) {
        let minimize = app.buttons["workout.header.minimize"]
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        let resume = app.buttons["Resume workout"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Today follows the live workout")
        XCTAssertTrue(app.staticTexts[name].exists, "the card is the workout's")
        check()
        resume.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workout.header.title"].label, name)
    }

    /// The app on a fresh database, its clock moved so that the launch happens at `instant`.
    @MainActor
    private func launch(at instant: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", instant]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }

    /// Saves the seed program as the active one, the only way a UI test has: the Debug menu's sample workout
    /// saves it and starts its first day, which is then discarded.
    @MainActor
    private func seedTheProgram(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        discardTheWorkout(in: app)
    }

    /// Finish, then Discard, on the cover that is up; returns once the cover is down.
    @MainActor
    private func discardTheWorkout(in app: XCUIApplication) {
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 5))
    }

    /// Whether `element` can be tapped within a few seconds: under a sheet or a cover it exists all along.
    @MainActor
    private func becomesHittable(_ element: XCUIElement) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [hittable], timeout: 5) == .completed
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
