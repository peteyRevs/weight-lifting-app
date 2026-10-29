import FeatureOnboarding
import FeatureWorkout
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
    /// The workout's presenter: which workout is showing over the tabs, if any (F10).
    @State private var workout = WorkoutLauncher()
    @State private var isDebugMenuShown = false
    #if DEBUG
        /// Set by the Debug menu's sample rows, to the day asked for: the workout starts once the menu's sheet
        /// is down, because a cover cannot go up over a sheet that is still there.
        @State private var sampleDay: Int?
    #endif
    private let composition: AppComposition
    /// Which screen `content` shows. `AppRoot` owns it and keeps it following the active program.
    private let gate: RootGate
    /// Makes the router the shell starts over with when onboarding appears.
    private let newRouter: @MainActor () -> AppRouter
    /// Hosted gate tests draw this for `.main`: SwiftUI would make Today's store outside their dependencies (F8-S3-4).
    private let mainStandIn: (@MainActor () -> AnyView)?

    /// `router`, `newRouter` and `mainStandIn` are for the tests, which push a screen through the router they
    /// hand over and keep the one the shell starts over with; the app's are new, and it draws the real tabs.
    init(
        composition: AppComposition,
        gate: RootGate,
        router: AppRouter = AppRouter(),
        newRouter: @escaping @MainActor () -> AppRouter = AppRouter.init,
        mainStandIn: (@MainActor () -> AnyView)? = nil
    ) {
        self.composition = composition
        self.gate = gate
        self.newRouter = newRouter
        self.mainStandIn = mainStandIn
        _router = State(initialValue: router)
    }

    /// What is presented over everything `content` shows: the workout's cover, its dialogs and its routes.
    var body: some View {
        content
            .workoutCover(workout) { router.resolve($0) }
    }

    /// Which screen the root shows (F08): the ground colour until the gate has its answer, then onboarding
    /// while there is no active program and the tabs while there is one. `MainRoot` stays in the tree
    /// throughout.
    ///
    /// When onboarding appears the shell starts over with a new router, out of sight (ruling R4): the tabs a
    /// lifter reaches after onboarding open on Today with every stack empty, the second time as the first. A
    /// program can go away under any tab and any pushed screen (Settings' "Delete all data", F14).
    ///
    /// Onboarding's "Retry" first runs the launch's seed step again (`AppComposition.retrySeed()`), which
    /// always returns.
    @ViewBuilder private var content: some View {
        switch gate.destination {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case .onboarding:
            OnboardingRoot { await composition.retrySeed() }
                .onAppear { router = newRouter() }
        case .main:
            if let mainStandIn {
                mainStandIn()
            } else {
                tabs
            }
        }
    }

    /// The tabs, with the Debug menu's sheet on them (the UI tests open it from `today.title`).
    private var tabs: some View {
        AppTabs(
            router: router,
            onTodayRoute: { router.resolve($0, workout: workout) },
            onProgramRoute: { router.resolve($0) },
            onLibraryRoute: { router.resolve($0) },
            onHistoryRoute: { router.resolve($0) },
            onTodayTitleLongPress: { isDebugMenuShown = true }
        )
        #if DEBUG
        .sheet(isPresented: $isDebugMenuShown, onDismiss: startSampleWorkoutIfAsked) {
            DebugMenu(actions: DebugMenu.Action.sampleWorkouts { day in
                sampleDay = day
                isDebugMenuShown = false
            }) { await composition.diagnostics() }
        }
        #endif
    }

    #if DEBUG
        private func startSampleWorkoutIfAsked() {
            guard let day = sampleDay else {
                return
            }
            sampleDay = nil
            workout.startSample(day: day)
        }
    #endif
}
