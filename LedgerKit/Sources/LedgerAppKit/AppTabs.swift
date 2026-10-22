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
/// Today draws `FeatureToday`'s root, Program `FeatureProgram`'s builder and Library `FeatureLibrary`'s root, each
/// handed where its routes go; the builder is also handed the week the router was last asked to select. History
/// shows a `PlaceholderScreen` until F13 replaces it, one line.
struct AppTabs: View {
    @Bindable var router: AppRouter
    /// Where Today's routes go: `MainRoot` resolves them with the router and the workout's presenter.
    var onTodayRoute: @MainActor (TodayRoute) -> Void = { _ in }
    /// Where the Program screens' routes go: `MainRoot` resolves them with the router.
    var onProgramRoute: @MainActor (ProgramRoute) -> Void = { _ in }
    /// Where the Library's routes go: `MainRoot` resolves them with the router.
    var onLibraryRoute: @MainActor (LibraryRoute) -> Void = { _ in }
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
                stack(.library) { LibraryRoot(onRoute: onLibraryRoute) }
            }
            Tab(AppCopy.title(of: .history), systemImage: "clock", value: AppTab.history) {
                stack(.history) { PlaceholderScreen(AppCopy.title(of: .history), identifier: "history.title") }
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
                    screen(for: destination)
                }
        }
        .tabContentTint()
    }

    @ViewBuilder
    private func screen(for destination: AppDestination) -> some View {
        switch destination {
        case .settings:
            PlaceholderScreen(AppCopy.settingsTitle, identifier: "settings.title")
        case let .day(day, weekIndex):
            // A screen and a store per route (ruling R8): another day pushed in its place is drawn anew.
            DayEditorRoot(day: day, weekIndex: weekIndex, onRoute: onProgramRoute)
                .id(destination)
        case .exercise:
            PlaceholderScreen(AppCopy.exerciseHistoryTitle, identifier: "library.history.title")
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
