import XCTest

/// Selected by the `PR` test plan as `LedgerUITests/Smoke`
/// (docs/testing-strategy.md §8).
final class Smoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_launchShowsPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Ledger"].waitForExistence(timeout: 10))
    }
}
