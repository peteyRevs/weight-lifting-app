import XCTest

/// Selected by the `PR` test plan as `LedgerUITests/Smoke` (docs/testing-strategy.md §8). F07 criterion 1: the app
/// launches on a fresh database (`-LEDGER_UITEST`) to Today.
final class Smoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launchesToToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launch()
        let title = app.staticTexts["today.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Today")
    }
}
