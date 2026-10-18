import XCTest

/// F07 criterion 1's launch time, measured and reported, never gated (product decision #30): Xcode's launch metric
/// over five launches, plus the app's own launch-to-first-frame as Diagnostics shows it, attached to the result.
/// Nightly only: the `PR` plan selects `Smoke` alone. It becomes a pass/fail check on a real iPhone in F20/F26.
final class LaunchPerformance: XCTestCase {
    @MainActor
    func test_launchToFirstFrame() {
        let app = XCUIApplication.fresh()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
        reportInAppMeasurement(app)
    }

    /// Reads the app's own measurement from Diagnostics (decision #30) and attaches it; reports, never fails.
    /// Diagnostics is behind onboarding on a fresh database, so it skips setup first (F08 S3). When it cannot
    /// get there, what it attaches is why, so a run without the figure says so.
    @MainActor
    private func reportInAppMeasurement(_ app: XCUIApplication) {
        do {
            try app.skipSetup()
        } catch {
            attach("No in-app figure: \(error.description)")
            return
        }
        app.staticTexts["today.title"].press(forDuration: 1)
        app.buttons["debug.menu.diagnostics"].tap()
        let launch = app.staticTexts["debug.diagnostics.launch"]
        if launch.waitForExistence(timeout: 10) {
            attach("In-app launch to first frame: \(launch.label)")
        } else {
            attach("No in-app figure: debug.diagnostics.launch did not appear within 10 s")
        }
    }

    @MainActor
    private func attach(_ report: String) {
        let attachment = XCTAttachment(string: report)
        attachment.name = "launchToFirstFrame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
