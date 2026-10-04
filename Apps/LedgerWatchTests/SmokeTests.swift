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

    /// The app hosting this test launched through `WatchComposition.launch()`, which boots nothing while tests run, so
    /// hosted tests neither open the app's database nor assign its handlers.
    @Test("The watch app links the LedgerWatchAppKit umbrella product, whose launch boots nothing under test")
    func umbrellaProduct_links_andLaunchBootsNothing() {
        #expect(WatchComposition.launch().state == .idle)
    }
}
