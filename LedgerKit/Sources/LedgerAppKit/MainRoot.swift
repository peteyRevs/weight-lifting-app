import LedgerDesign
import SwiftUI

/// What the root draws once the database is open: the tab shell over the app's router and, in Debug builds, the
/// debug menu a long press on Today's title opens (F07 criterion 7).
///
/// It is also where the app resolves routes (architecture §4): it owns the router and the presenters of the
/// features that present themselves over the tabs, builds each feature's `onRoute` from them, and hands it to
/// `AppTabs`. The other features' root changes land in its three members, one each: `body`, `content`, `tabs`.
struct MainRoot: View {
    /// `@State` keeps the first router and drops the one each later `init` builds, which costs a small class
    /// with no work in its initializer. A presenter beside it follows the same rule: nothing in its `init`.
    @State private var router = AppRouter()
    @State private var isDebugMenuShown = false
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    /// What is presented over everything `content` shows: F10 adds the workout's cover modifier here.
    var body: some View {
        content
    }

    /// Which screen the root shows: F08 adds its "no active program" branch here, around `tabs`.
    private var content: some View {
        tabs
    }

    /// The tabs, with the Debug menu's sheet on them (the UI tests open it from `today.title`).
    private var tabs: some View {
        AppTabs(router: router) { isDebugMenuShown = true }
        #if DEBUG
            .sheet(isPresented: $isDebugMenuShown) {
                DebugMenu { await composition.diagnostics() }
            }
        #endif
    }
}
