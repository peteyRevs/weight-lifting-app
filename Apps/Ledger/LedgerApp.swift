import LedgerAppKit
import SwiftUI

@main
struct LedgerApp: App {
    /// Takes up the watch's mirrored session when the system relaunches the app for it (F16).
    @UIApplicationDelegateAdaptor private var delegate: PhoneAppDelegate
    /// Built in `App.init`: the mirroring handler is assigned and the database opened before the first frame
    /// (`AppComposition.launch()`, which boots nothing when the process hosts unit tests).
    @State private var composition = AppComposition.launch()

    var body: some Scene {
        WindowGroup {
            AppRoot(composition: composition)
        }
    }
}
