import XCTest

/// F14 S3, criterion 6, on screen: Settings → "Delete all data" → the warning's "Continue" → the word typed → "Delete
/// everything", and the app shows onboarding; finishing it shows Today again. Nightly only: the `PR` plan selects
/// `Smoke`. That the erase empties the database is `DataResetTests`' and `DeleteAllGateTests`'.
final class SettingsDeleteAll: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_deleteAllData_confirmedTwice_showsOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))

        let row = app.buttons["settings.deleteAll"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0 ..< 4 where !row.isHittable {
            app.swipeUp()
        }
        row.tap()
        let warning = app.alerts["Delete all data?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "the warning")
        warning.buttons["Continue"].tap()

        let field = app.textFields["settings.deleteAll.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the sheet's field")
        let confirm = app.buttons["settings.deleteAll.confirm"]
        XCTAssertFalse(confirm.isEnabled, "dimmed until the word is typed")
        field.tap()
        field.typeText("DELETE")
        XCTAssertTrue(confirm.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Typed"
        attachment.lifetime = .keepAlways
        add(attachment)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 10), "onboarding, as a new install")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10), "Today again")
    }
}
