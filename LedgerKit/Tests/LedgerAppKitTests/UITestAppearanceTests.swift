@testable import LedgerAppKit
import SwiftUI
import Testing

/// fix/tabs-audit: a UI test's own appearance, `-LEDGER_UITEST_APPEARANCE light|dark` beside `-LEDGER_UITEST`.
@Suite("UITestAppearance")
struct UITestAppearanceTests {
    @Test("Each value is its appearance", arguments: [("light", ColorScheme.light), ("dark", .dark)])
    func colorScheme_readsTheValue(_ value: String, _ scheme: ColorScheme) throws {
        let arguments = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_APPEARANCE", value]
        #expect(try UITestAppearance.colorScheme(arguments: arguments) == scheme)
    }

    @Test("Without the argument the device's appearance is kept")
    func colorScheme_withoutTheArgument_isNil() throws {
        #expect(try UITestAppearance.colorScheme(arguments: ["Ledger", "-LEDGER_UITEST", "1"]) == nil)
    }

    @Test("Without -LEDGER_UITEST the argument is ignored, whatever its value")
    func colorScheme_withoutTheUITestArgument_isNil() throws {
        #expect(try UITestAppearance.colorScheme(arguments: ["Ledger", "-LEDGER_UITEST_APPEARANCE", "dark"]) == nil)
        #expect(try UITestAppearance.colorScheme(arguments: ["Ledger", "-LEDGER_UITEST_APPEARANCE", "dim"]) == nil)
    }

    @Test("A value that is neither light nor dark, or none, is an error", arguments: [["Dark"], ["dim"], [""], []])
    func colorScheme_otherValue_throws(_ value: [String]) {
        let arguments = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_APPEARANCE"] + value
        #expect(throws: UITestAppearance.InvalidAppearance(value: value.first)) {
            try UITestAppearance.colorScheme(arguments: arguments)
        }
    }

    @Test("The live environment carries what the arguments ask for")
    @MainActor
    func liveEnvironment_carriesTheAppearance() {
        let arguments = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_APPEARANCE", "dark"]
        #expect(AppComposition.Environment.live(arguments: arguments).colorScheme == .dark)
        #expect(AppComposition.Environment.live(arguments: ["Ledger"]).colorScheme == nil)
    }
}
