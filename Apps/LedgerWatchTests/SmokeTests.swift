@testable import LedgerWatch
import LedgerWatchAppKit
import Testing
import UIKit

@MainActor
@Suite("Smoke")
struct SmokeTests {
    @Test("The Archivo variable font is registered from the watch bundle")
    func archivo_isRegistered() {
        #expect(UIFont.familyNames.contains("Archivo"))
    }

    @Test("The watch app links the LedgerWatchAppKit umbrella product")
    func umbrellaProduct_links() {
        #expect(LedgerWatchAppKitModule.name == "LedgerWatchAppKit")
    }
}
