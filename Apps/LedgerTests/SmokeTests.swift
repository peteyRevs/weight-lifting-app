@testable import Ledger
import LedgerAppKit
import Testing
import UIKit

@MainActor
@Suite("Smoke")
struct SmokeTests {
    @Test("The Archivo variable font is registered from the app bundle")
    func archivo_isRegistered() {
        #expect(UIFont.familyNames.contains("Archivo"))
    }

    /// The app hosting this test launched through `AppComposition.launch()`, which boots nothing while tests run, so
    /// hosted tests neither open the app's database nor assign its handlers.
    @Test("The app links the LedgerAppKit umbrella product, whose launch boots nothing under test")
    func umbrellaProduct_links_andLaunchBootsNothing() {
        #expect(AppComposition.launch().state == .idle)
    }
}
