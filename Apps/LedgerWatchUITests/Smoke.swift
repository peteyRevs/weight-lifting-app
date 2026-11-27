import XCTest

/// Selected by the `PR-Watch` test plan as `LedgerWatchUITests/Smoke` (docs/testing-strategy.md §8). F07 criterion 2:
/// the watch app launches on its own fresh database (`-LEDGER_UITEST`) to the screen before a workout, whose title is
/// `today.title`. A fresh database holds no program until the phone sends one (F19), so it reads "No program on watch"
/// (F18 criterion 16).
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
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "No program on watch")
    }
}
