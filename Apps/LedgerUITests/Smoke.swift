import XCTest

/// Selected by the `PR` test plan as `LedgerUITests/Smoke` (docs/testing-strategy.md §8). F07 criterion 1 and F08
/// S3 criteria 1 and 3: the app launches on a fresh database (`-LEDGER_UITEST`) to onboarding, full screen, and
/// "Skip setup" lands on Today, with the tabs.
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
        XCTAssertEqual(app.staticTexts["today.title"].label, "Today")
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(onboarding.exists)
    }
}
