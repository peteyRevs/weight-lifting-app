@testable import Ledger
import LedgerAppKit
import Testing
import UIKit

@Suite("Smoke")
struct SmokeTests {
    @Test("The Archivo variable font is registered from the app bundle")
    func archivo_isRegistered() {
        #expect(UIFont.familyNames.contains("Archivo"))
    }

    @Test("The app links the LedgerAppKit umbrella product")
    func umbrellaProduct_links() {
        #expect(LedgerAppKitModule.name == "LedgerAppKit")
    }
}
