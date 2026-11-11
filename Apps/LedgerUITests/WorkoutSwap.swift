import XCTest

/// F10 S8b, criteria 13, 14, 18 and 28, on screen: the swap in the running app. The sample workout's bench
/// press is swapped from the card's "Swap exercise" for the sheet's first row; the card's name reads that
/// row's name; a set is logged, "Swap exercise" is gone (S8 ruling Q2), and the workout is saved; the
/// receipt lists the replacement. Each check reads the thing it names. Nightly only: the `PR` plan selects
/// `Smoke`.
final class WorkoutSwap: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_swapTheFirstExercise_logFinish_receiptListsTheReplacement() throws {
        let app = startSampleWorkout()
        let title = app.staticTexts["workout.card.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Barbell Bench Press")
        let swap = app.buttons["workout.card.swap"]
        XCTAssertTrue(swap.exists)
        XCTAssertEqual(swap.label, "Swap exercise")
        swap.tap()

        let row = app.buttons["workout.swap.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sheet's rows are read")
        XCTAssertTrue(app.staticTexts["Same movement pattern."].exists)
        attachScreenshot(of: app, named: "Swap sheet")
        let name = try XCTUnwrap(row.label.components(separatedBy: ", ").first)
        XCTAssertEqual(name, "Dumbbell Bench Press")
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the sheet goes down")
        let swapped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", name), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [swapped], timeout: 5), .completed, "the card reads the row's name")

        app.buttons["Log set 1"].tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(swap.exists, "with a set logged the exercise is not offered for a swap")
        saveAndFindOnTheReceipt(name, in: app)
    }

    /// Launches on the seed program and starts the Debug menu's sample workout (the seed's Upper A).
    @MainActor
    private func startSampleWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.press(forDuration: 1)
        let sample = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        return app
    }

    /// "Finish", "Save workout", then the receipt's row of the exercise named `name`; "Done" closes it.
    @MainActor
    private func saveAndFindOnTheReceipt(_ name: String, in app: XCUIApplication) {
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let done = app.buttons["workout.receipt.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let listed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name), ")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5), "the receipt lists the replacement")
        attachScreenshot(of: app, named: "Receipt after a swap")
        done.tap()
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
