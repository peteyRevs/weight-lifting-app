import SwiftUI

/// A UI test's own appearance for the app (fix/tabs-audit): `-LEDGER_UITEST_APPEARANCE light|dark` beside
/// `-LEDGER_UITEST` draws the whole app, the system's tab bar too, in that appearance whatever the device's.
///
/// It exists because the device's cannot be relied on: on the iOS 27.0 simulator (iPhone 17, locally and on the
/// nightly's runner), `XCUIDevice.shared.appearance = .dark` and `simctl ui appearance dark` both read back dark
/// while every app, the system's Settings too, goes on drawing light. A test that asks for dark that way audits
/// and measures light.
///
/// Read as `UITestClock` reads its argument, and like it **in Debug builds only**: a Release build reads no
/// argument here and follows the device.
nonisolated enum UITestAppearance {
    static let argument = "-LEDGER_UITEST_APPEARANCE"

    /// The argument is there and its value is missing or is neither "light" nor "dark".
    struct InvalidAppearance: Error, Equatable {
        let value: String?
    }

    /// The appearance the arguments ask for; nil when they ask for none, or are not a UI test's.
    static func colorScheme(arguments: [String]) throws -> ColorScheme? {
        guard arguments.contains("-LEDGER_UITEST"), let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: throw InvalidAppearance(value: value)
        }
    }

    /// `colorScheme(arguments:)` for this launch. A value that cannot be read stops the launch, as a wrong date
    /// does: a test that asked for dark must not run in light and pass.
    static func liveColorScheme(arguments: [String]) -> ColorScheme? {
        #if DEBUG
            do {
                return try colorScheme(arguments: arguments)
            } catch {
                fatalError("\(argument) takes light or dark: \(error)")
            }
        #else
            return nil
        #endif
    }
}
