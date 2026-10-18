import XCTest

/// Why a UI test did not get from onboarding to Today: which of the helper's two waits ran out, and what the
/// app showed then. Eleven of the UI tests start through that helper, so this is the first thing to know when
/// they fail together (F08 S3, review S3-N2).
enum SkipSetupFailure: Error, Equatable, CustomStringConvertible {
    /// "Skip setup" never came. With `isTodayShown` the app opened on the tabs, not on onboarding.
    case noSkipButton(isTodayShown: Bool)
    /// Today's title did not come after the tap. With `isErrorShown` onboarding says its save failed;
    /// without, the program was saved, or is still being saved, and the root did not switch.
    case noToday(isErrorShown: Bool)

    var description: String {
        switch self {
        case let .noSkipButton(isTodayShown):
            "onboarding.skip did not appear within 10 s (today.title shown: \(isTodayShown))"
        case let .noToday(isErrorShown):
            "today.title did not appear within 10 s of Skip setup (onboarding.error shown: \(isErrorShown))"
        }
    }
}

/// How the UI tests start the app and get past onboarding (F08 S3).
///
/// Every UI test launches with `-LEDGER_UITEST 1`, which gives the app a fresh database in a new temporary
/// directory. A fresh database has no program, so the app opens on onboarding, and a test that is about
/// anything behind it first gets to Today as a lifter who skips setup does. This is the one place that knows
/// how: when F15's seeded launch mode exists, `skipSetup()` is where a launch with a program replaces the tap.
extension XCUIApplication {
    /// The app, not yet launched, with the arguments of a UI test and then `arguments`.
    @MainActor
    static func fresh(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        return app
    }

    /// From onboarding to Today: taps "Skip setup", which saves the default program, and waits for Today's
    /// title. Throws which of the two waits ran out.
    @MainActor
    func skipSetup() throws(SkipSetupFailure) {
        let skip = buttons["onboarding.skip"]
        guard skip.waitForExistence(timeout: 10) else {
            throw .noSkipButton(isTodayShown: staticTexts["today.title"].exists)
        }
        skip.tap()
        guard staticTexts["today.title"].waitForExistence(timeout: 10) else {
            throw .noToday(isErrorShown: staticTexts["onboarding.error"].exists)
        }
    }

    /// `skipSetup()` for a test's assertion: true on Today. When a wait ran out it is false, and which wait is
    /// recorded as the test's failure at the caller's line, so the failure says more than "false".
    @MainActor
    func skipSetupToToday(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        do {
            try skipSetup()
            return true
        } catch {
            XCTFail(error.description, file: file, line: line)
            return false
        }
    }
}
