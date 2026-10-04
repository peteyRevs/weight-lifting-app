import LedgerWatchAppKit
import SwiftUI

@main
struct LedgerWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    /// Built in `App.init`: the database opens before the first frame (`WatchComposition.launch()`, which boots
    /// nothing when the process hosts unit tests).
    @State private var composition = WatchComposition.launch()

    var body: some Scene {
        WindowGroup {
            WatchRoot(composition: composition)
        }
    }
}
