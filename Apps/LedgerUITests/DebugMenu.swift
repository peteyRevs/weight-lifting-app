import XCTest

/// F07 criteria 1 and 7, the data half on screen: the debug menu opens from a long press on Today's title, and
/// Diagnostics shows the database in Application Support's place for a UI test (a fresh temporary file), the catalog
/// seeded (at least 200 exercise rows), and swift-dependencies' live context in an app a UI test launched.
final class DebugMenu: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_diagnostics_showsTheSeededCatalog() throws {
        let app = XCUIApplication.fresh()
        app.launch()
        XCTAssertTrue(app.skipSetupToToday())
        let title = app.staticTexts["today.title"]

        attachScreenshot(of: app, named: "Today")
        title.press(forDuration: 1)
        let diagnostics = app.buttons["debug.menu.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["debug.menu.designGallery"].exists)
        diagnostics.tap()

        let exercises = app.staticTexts["debug.diagnostics.rows.exercise"]
        XCTAssertTrue(exercises.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(Int(exercises.label)), 200)
        attachScreenshot(of: app, named: "Diagnostics")
        XCTAssertTrue(app.staticTexts["debug.diagnostics.path"].label.hasSuffix("/ledger.sqlite"))
        XCTAssertEqual(app.staticTexts["debug.diagnostics.context"].label, "live")
        XCTAssertTrue(app.staticTexts["debug.diagnostics.launch"].label.hasSuffix(" ms"))
        let device = app.staticTexts["debug.diagnostics.deviceID"].label
        XCTAssertNotNil(UUID(uuidString: device), device)
        XCTAssertNotEqual(device, "00000000-0000-0000-0000-000000000000")
    }

    /// Kept with the result, so a run shows the screens it checked (the M0 exit's screenshots).
    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
