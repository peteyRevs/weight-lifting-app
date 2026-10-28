import XCTest

/// F12 S3, on screen, over the seed program (`BuilderApp`): "New exercise" in the Library creates the lifter's own
/// exercise, which the Library lists as Custom and the Day editor's exercise library offers (the DoD's round trip
/// through the picker; the swap part is F10 S8's); "Edit" on its history renames it (criterion 10). And a row of a
/// saved workout's receipt opens that exercise's history on Today's stack (N18). Nightly only: the `PR` plan selects
/// `Smoke`.
final class LibraryCreate: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_newExercise_isListedAndPicked_andEditRenamesIt() {
        let app = BuilderApp.launch(at: Builder.week5)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.title"].waitForExistence(timeout: 10))
        create("Landmine Squeeze Press", in: app)

        let search = app.textFields.firstMatch
        search.tap()
        search.typeText("Squeeze")
        let row = app.buttons["Landmine Squeeze Press"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the Library lists it")
        XCTAssertTrue((row.value as? String ?? "").contains("Custom"), "\(row.value ?? "")")
        row.tap()
        let title = app.staticTexts["library.history.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Landmine Squeeze Press")
        rename(adding: " Hold", in: app)
        let renamed = NSPredicate(format: "label == %@", "Landmine Squeeze Press Hold")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: renamed, evaluatedWith: title)], timeout: 5), .completed)
        attachScreenshot(of: app, named: "The history, renamed")

        BuilderApp.openUpperA(in: app)
        let open = app.buttons["+ Add exercise from library"]
        BuilderApp.scrollUntilHittable(open, in: app)
        open.tap()
        let library = app.textFields["Search exercises"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        library.typeText("Squeeze")
        XCTAssertTrue(app.buttons["Landmine Squeeze Press Hold"].firstMatch.waitForExistence(timeout: 5), "picked too")
        attachScreenshot(of: app, named: "The exercise library offers it")
    }

    /// "New exercise": Save with no name shows its line; then the name typed and Save closes the sheet.
    @MainActor
    private func create(_ exercise: String, in app: XCUIApplication) {
        app.buttons["New exercise"].firstMatch.tap()
        let name = app.textFields["library.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let save = app.buttons["library.create.save"]
        save.tap()
        XCTAssertTrue(app.staticTexts["Enter a name."].waitForExistence(timeout: 5), "a blank name is refused")
        name.tap()
        name.typeText(exercise)
        app.buttons["Equipment: Barbell"].firstMatch.tap()
        attachScreenshot(of: app, named: "New exercise, filled in")
        save.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the sheet closed once saved")
    }

    /// "Edit" on the history: the sheet opens filled in; `suffix` typed after the name, and Save.
    @MainActor
    private func rename(adding suffix: String, in app: XCUIApplication) {
        let edit = app.buttons["library.history.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "its history has Edit")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit exercise"].waitForExistence(timeout: 5))
        let name = app.textFields["library.create.name"]
        XCTAssertEqual(name.value as? String, "Landmine Squeeze Press", "the sheet opens filled in")
        name.tap()
        name.typeText(suffix)
        app.buttons["library.create.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func test_receiptRow_opensTheExercisesHistoryOnToday() {
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
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        app.buttons["Log set 1"].tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt shows")

        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Prescribed ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "a receipt row is a button")
        let exercise = String(first.label.prefix { $0 != "," })
        attachScreenshot(of: app, named: "The receipt")
        first.tap()
        let title = app.staticTexts["library.history.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the history is pushed")
        XCTAssertEqual(title.label, exercise)
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected, "on Today's stack")
        attachScreenshot(of: app, named: "The exercise's history on Today")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(today.waitForExistence(timeout: 5), "back is Today")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
