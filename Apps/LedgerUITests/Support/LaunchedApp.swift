import XCTest

/// How the UI tests start the app and get past onboarding (F08 S3).
///
/// Every UI test launches with `-LEDGER_UITEST 1`, which gives the app a fresh database in a new temporary
/// directory. A fresh database has no program, so the app opens on onboarding, and a test that is about
/// anything behind it first gets to Today as a lifter who skips setup does. This is the one place that knows
/// how: when F15's seeded launch mode exists, `skipSetupToToday()` is where a launch with a program replaces
/// the tap.
extension XCUIApplication {
    /// The app, not yet launched, with the arguments of a UI test and then `arguments`.
    @MainActor
    static func fresh(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        return app
    }

    /// From onboarding to Today: taps "Skip setup", which saves the default program, and waits for Today's
    /// title. False when onboarding's button or Today's title does not come.
    @MainActor
    func skipSetupToToday() -> Bool {
        let skip = buttons["onboarding.skip"]
        guard skip.waitForExistence(timeout: 10) else {
            return false
        }
        skip.tap()
        return staticTexts["today.title"].waitForExistence(timeout: 10)
    }
}
