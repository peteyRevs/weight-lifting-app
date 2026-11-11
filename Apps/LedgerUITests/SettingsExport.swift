import XCTest

/// F14 S2, criterion 5, on screen: "Export data · CSV" presents the system's share sheet. Presentation only: what
/// the sheet does with the file is the system's, and the file's bytes are `SettingsPlatesExportStoreTests`'. Share
/// sheet automation is known to be flaky (the brief's risk), so this runs nightly only: the `PR` plan selects `Smoke`.
final class SettingsExport: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_export_presentsTheShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))

        let export = app.buttons["settings.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        for _ in 0 ..< 4 where !export.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(export.label, "Export data, CSV")
        export.tap()
        // The system's share sheet: an activity list, whatever the extensions it offers.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the share sheet appeared")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Share sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
