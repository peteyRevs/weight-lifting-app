import FeatureHistory
import FeatureLibrary
import FeatureProgram
import FeatureToday
import LedgerDesign
import SwiftUI

/// The tab shell (product decision #1): Today, Program, Library and History, each with its own navigation stack
/// over the router's path for that tab. The tab bar is the system's (architecture §11), with Apple's stock symbols
/// until custom icons replace them; its selected tab is tinted `LedgerColor.accentText`, the accent that meets AA
/// contrast in both themes, and each stack sets the tint back to the system's, so that nothing a tab draws is
/// tinted unless the screen tints it (product decision #17: the accent once per screen).
///
/// Today draws `FeatureToday`'s root, Program `FeatureProgram`'s builder, Library `FeatureLibrary`'s root and History
/// `FeatureHistory`'s, each handed where its routes go; the builder is also handed the week the router was last asked
/// to select. The Library's and History's screens can stand on any tab's stack, so their routes go with the tab
/// whose stack drew them (F13-S1-6): a route handed over late still lands on the stack it came from.
struct AppTabs: View {
    @Bindable var router: AppRouter
    /// Where Today's routes go: `MainRoot` resolves them with the router and the workout's presenter.
    var onTodayRoute: @MainActor (TodayRoute) -> Void = { _ in }
    /// Where the Program screens' routes go: `MainRoot` resolves them with the router.
    var onProgramRoute: @MainActor (ProgramRoute) -> Void = { _ in }
    /// Where the Library's routes go, with the tab whose screen sent them: `MainRoot` resolves them with the router.
    var onLibraryRoute: @MainActor (LibraryRoute, AppTab) -> Void = { _, _ in }
    /// Where the History screens' routes go, with the tab whose screen sent them: `MainRoot` resolves them with the
    /// router.
    var onHistoryRoute: @MainActor (HistoryRoute, AppTab) -> Void = { _, _ in }
    /// Debug builds: opens the debug menu (F07 criterion 7).
    var onTodayTitleLongPress: () -> Void = {}

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab(AppCopy.title(of: .today), systemImage: "chart.bar", value: AppTab.today) {
                stack(.today) { TodayRoot(onRoute: onTodayRoute, onTitleLongPress: onTodayTitleLongPress) }
            }
            Tab(AppCopy.title(of: .program), systemImage: "calendar", value: AppTab.program) {
                stack(.program) { ProgramRoot(week: router.programWeek, onRoute: onProgramRoute) }
            }
            Tab(AppCopy.title(of: .library), systemImage: "dumbbell", value: AppTab.library) {
                stack(.library) { LibraryRoot { onLibraryRoute($0, .library) } }
            }
            Tab(AppCopy.title(of: .history), systemImage: "clock", value: AppTab.history) {
                stack(.history) { HistoryRoot { onHistoryRoute($0, .history) } }
            }
        }
        .tint(LedgerColor.accentText)
    }

    /// `tab`'s navigation stack: `root` under the router's path for the tab, with the one registration of
    /// `AppDestination` that lets any tab push any screen.
    private func stack(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: $router[path: tab]) {
            root()
                .tabRootChrome()
                .navigationDestination(for: AppDestination.self) { destination in
                    screen(for: destination, in: tab)
                }
        }
        .tabContentTint()
    }

    /// The screen of `destination`, on `tab`'s stack.
    @ViewBuilder
    private func screen(for destination: AppDestination, in tab: AppTab) -> some View {
        switch destination {
        case .settings:
            PlaceholderScreen(AppCopy.settingsTitle, identifier: "settings.title")
        case let .day(day, weekIndex):
            // A screen and a store per route (ruling R8): another day pushed in its place is drawn anew.
            DayEditorRoot(day: day, weekIndex: weekIndex, onRoute: onProgramRoute)
                .id(destination)
        case let .exercise(id):
            ExerciseHistoryRoot(exercise: id) { onLibraryRoute($0, tab) }
                .id(destination)
        case let .workout(id):
            WorkoutDetailRoot(workout: id) { onHistoryRoute($0, tab) }
                .id(destination)
        }
    }
}

extension View {
    /// A tab's root draws its own title, so the stack's navigation bar is hidden there; a pushed screen keeps
    /// the bar and its back button.
    fileprivate func tabRootChrome() -> some View {
        #if os(iOS)
            toolbarVisibility(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    /// Ends the tab bar's tint here: what this view holds has the system's tint again, as if no tab view were
    /// around it. `AppTabs` applies it to each tab's stack.
    func tabContentTint() -> some View {
        tint(AnyShapeStyle?.none)
    }
}
