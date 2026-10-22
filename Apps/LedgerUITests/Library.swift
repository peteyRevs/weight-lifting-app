import XCTest

/// F12 S1, criteria 2 and 3, on screen: the Library tab in the running app over a fresh database (the bundled
/// catalog, no history): a query typed, two chips tapped, the one row left tapped, which pushes the exercise's
/// history on the Library's stack; back returns to the Library as it was. Nightly only:
/// the `PR` plan selects `Smoke`.
final class Library: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_queryChipsRow_opensTheHistory_andBackKeepsTheFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        let title = app.staticTexts["library.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Library")
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.label.hasPrefix("Search ") && search.label.hasSuffix(" exercises"), search.label)
        search.tap()
        search.typeText("row")
        app.buttons["Muscle: Back"].tap()
        app.buttons["Equipment: Machine"].tap()
        XCTAssertTrue(app.buttons["Muscle: Back"].isSelected)
        XCTAssertTrue(app.buttons["Equipment: Machine"].isSelected)
        let row = app.buttons["Chest-Supported Row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Barbell Row"].exists, "the filter leaves Chest-Supported Row alone")
        attachScreenshot(of: app, named: "Library, row, Back, Machine")
        row.tap()
        let history = app.staticTexts["library.history.title"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertEqual(history.label, "Chest-Supported Row")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Equipment: Machine"].isSelected, "the Library is as it was left")
        XCTAssertTrue(app.buttons["Chest-Supported Row"].exists)
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
