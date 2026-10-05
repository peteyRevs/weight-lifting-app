import LedgerDesign
import SwiftUI

/// What the root draws once the database is open: the tab shell over the app's router and, in Debug builds, the
/// debug menu a long press on Today's title opens (F07 criterion 7).
///
/// This is the one view the other features' root changes land in: F08 puts its "no active program" branch around
/// the tabs, and F10 hangs the workout's cover on them.
struct MainRoot: View {
    @State private var router = AppRouter()
    @State private var isDebugMenuShown = false
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    var body: some View {
        AppTabs(router: router) { isDebugMenuShown = true }
        #if DEBUG
            .sheet(isPresented: $isDebugMenuShown) {
                DebugMenu { await composition.diagnostics() }
            }
        #endif
    }
}
