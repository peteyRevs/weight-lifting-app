import XCTest

/// F10 S9 on screen: a superset drawn as one block and logged round by round in the running app. The sample
/// workout (the seed's Upper A) ends with Lat Pulldown and Cable Lateral Raise as a superset: a tap on Lat
/// Pulldown in "REMAINING" shows the block, "Superset · block 4 of 4" over "Round 1 of 3"; A1 logged starts
/// no rest and hands the shown row to B1; B1 logged starts the group's rest, whose panel names A2 next;
/// "Skip rest", and the title reads "Round 2 of 3". Each check reads the thing it names. Nightly only: the
/// `PR` plan selects `Smoke`.
final class WorkoutSuperset: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_superset_loggedRoundByRound() {
        let app = startSampleWorkout()
        let lat = app.buttons["workout.remaining.row.3"]
        XCTAssertTrue(lat.waitForExistence(timeout: 10))
        XCTAssertTrue(lat.label.hasPrefix("Lat Pulldown, "), lat.label)
        lat.tap()

        let title = app.staticTexts["workout.block.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the superset is drawn as one block")
        XCTAssertEqual(title.label, "Round 1 of 3")
        XCTAssertTrue(app.staticTexts["Superset · block 4 of 4"].exists)
        XCTAssertTrue(app.buttons["workout.block.legend.A"].isSelected, "A holds the shown row")
        XCTAssertFalse(app.buttons["workout.block.legend.B"].isSelected)
        attachScreenshot(of: app, named: "Superset, round 1")

        // A1 ends no round: no rest, and the shown row is B1.
        app.buttons["Log set A1"].tap()
        XCTAssertTrue(app.buttons["Undo set A1"].waitForExistence(timeout: 5))
        let skip = app.buttons["workout.rest.skip"]
        XCTAssertFalse(skip.exists, "a member that ends no round starts no rest")
        let rowB1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cable Lateral Raise, set 1, "))
            .firstMatch
        XCTAssertEqual(rowB1.value as? String, "Current set")
        XCTAssertTrue(app.buttons["workout.block.legend.B"].isSelected, "B holds the shown row")

        // B1 ends the round: the group's rest, and its panel names A2 next.
        app.buttons["Log set B1"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "the round's last member starts the group's rest")
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        XCTAssertTrue(status.label.hasPrefix("Resting, Lat Pulldown, set 2, "), status.label)
        attachScreenshot(of: app, named: "Superset, the group's rest")

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertEqual(title.label, "Round 2 of 3")
        XCTAssertTrue(app.buttons["workout.block.legend.A"].isSelected, "A2 is the shown row")
        discard(in: app)
    }

    /// Launches on the seed program and starts the Debug menu's sample workout (the seed's Upper A).
    @MainActor
    private func startSampleWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.press(forDuration: 1)
        let sample = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        return app
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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
