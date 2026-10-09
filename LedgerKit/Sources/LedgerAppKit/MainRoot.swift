import FeatureWorkout
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
    /// The workout's presenter: which workout is showing over the tabs, if any (F10).
    @State private var workout = WorkoutLauncher()
    @State private var isDebugMenuShown = false
    #if DEBUG
        /// Set by the Debug menu's sample rows, to the day asked for: the workout starts once the menu's sheet
        /// is down, because a cover cannot go up over a sheet that is still there.
        @State private var sampleDay: Int?
    #endif
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    /// What is presented over everything `content` shows: the workout's cover, its dialogs and its routes.
    var body: some View {
        content
            .workoutCover(workout) { router.resolve($0) }
    }

    /// Which screen the root shows: F08 adds its "no active program" branch here, around `tabs`.
    private var content: some View {
        tabs
    }

    /// The tabs, with the Debug menu's sheet on them (the UI tests open it from `today.title`).
    private var tabs: some View {
        AppTabs(router: router) { isDebugMenuShown = true }
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
