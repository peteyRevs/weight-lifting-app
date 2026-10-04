import XCTest

/// F07 criterion 1's launch time, measured and reported, never gated (product decision #30): Xcode's launch metric
/// over five launches, plus the app's own launch-to-first-frame as Diagnostics shows it, attached to the result.
/// Nightly only: the `PR` plan selects `Smoke` alone. It becomes a pass/fail check on a real iPhone in F20/F26.
final class LaunchPerformance: XCTestCase {
    @MainActor
    func test_launchToFirstFrame() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
        reportInAppMeasurement(app)
    }

    /// Reads the app's own measurement from Diagnostics (decision #30) and attaches it; reports, never fails.
    @MainActor
    private func reportInAppMeasurement(_ app: XCUIApplication) {
        let title = app.staticTexts["today.title"]
        guard title.waitForExistence(timeout: 10) else {
            return
        }
        title.press(forDuration: 1)
        app.buttons["debug.menu.diagnostics"].tap()
        let launch = app.staticTexts["debug.diagnostics.launch"]
        if launch.waitForExistence(timeout: 10) {
            let attachment = XCTAttachment(string: "In-app launch to first frame: \(launch.label)")
            attachment.name = "launchToFirstFrame"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
