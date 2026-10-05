import FeatureOnboarding
import LedgerDesign
import SwiftUI

/// What the root draws once the database is open: onboarding while there is no active program (F08), else the
/// tab shell over the app's router and, in Debug builds, the debug menu a long press on Today's title opens
/// (F07 criterion 7).
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
    /// Which screen `content` shows. `AppRoot` owns it and keeps it following the active program.
    private let gate: RootGate

    init(composition: AppComposition, gate: RootGate) {
        self.composition = composition
        self.gate = gate
    }

    /// What is presented over everything `content` shows: F10 adds the workout's cover modifier here.
    var body: some View {
        content
    }

    /// Which screen the root shows (F08): the ground colour until the gate has its answer, then onboarding
    /// while there is no active program and the tabs while there is one. `MainRoot` stays in the tree
    /// throughout and keeps the router: after a first run the tabs appear with Today selected.
    ///
    /// Onboarding's "Retry" first runs the launch's pass again, in the foreground, which is where a failed seed
    /// is retried (product decision #28; `DatabaseLaunch.resume`). The call always returns: every step it
    /// reaches is one task of the launch's own that ends in an outcome, a local transaction that commits or
    /// throws, and nothing in it waits for the lifter or for a network.
    @ViewBuilder private var content: some View {
        switch gate.destination {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case .onboarding:
            OnboardingRoot { await composition.resume(in: .active) }
        case .main:
            tabs
        }
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
