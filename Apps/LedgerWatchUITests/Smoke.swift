import XCTest

/// Selected by the `PR-Watch` test plan as `LedgerWatchUITests/Smoke`
/// (docs/testing-strategy.md §8).
final class Smoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_launchShowsPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Ledger"].waitForExistence(timeout: 20))
    }
}
