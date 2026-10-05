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
    @State private var router: AppRouter
    @State private var isDebugMenuShown = false
    private let composition: AppComposition
    /// Which screen `content` shows. `AppRoot` owns it and keeps it following the active program.
    private let gate: RootGate

    /// `router` is for the tests, which push a screen through the one they hand over; the app's is new.
    init(composition: AppComposition, gate: RootGate, router: AppRouter = AppRouter()) {
        self.composition = composition
        self.gate = gate
        _router = State(initialValue: router)
    }

    /// What is presented over everything `content` shows: F10 adds the workout's cover modifier here.
    var body: some View {
        content
    }

    /// Which screen the root shows (F08): the ground colour until the gate has its answer, then onboarding
    /// while there is no active program and the tabs while there is one. `MainRoot` stays in the tree
    /// throughout and keeps the router.
    ///
    /// When onboarding appears the shell starts over, out of sight: the tabs a lifter reaches after onboarding
    /// open on Today with every stack empty, the second time as the first. A program can go away under any
    /// tab and any pushed screen (Settings' "Delete all data", F14).
    ///
    /// Onboarding's "Retry" first runs the launch's seed step again (`AppComposition.retrySeed()`, ruling O13),
    /// which always returns.
    @ViewBuilder private var content: some View {
        switch gate.destination {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case .onboarding:
            OnboardingRoot { await composition.retrySeed() }
                .onAppear { router.reset() }
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
