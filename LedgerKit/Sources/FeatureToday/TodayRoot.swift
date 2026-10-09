import SwiftUI

/// Today in the app (F09 S5): the screen over its store. It owns the store and runs its work from its tasks,
/// so nothing outlives the view; the app hands it `onRoute`, which resolves where a tap goes (architecture §4),
/// and, in Debug builds, what a long press on the title does.
///
/// **The store's task restarts whenever the scene's phase changes**, and SwiftUI restarts it when the tab
/// comes back on screen. A restart keeps the model on screen and reads everything again, which is how Today
/// shows a new day, or a workout changed in History, when the lifter comes back to it.
///
/// **A route is handed on once.** The screen's taps go to the store, which keeps one route waiting; the task
/// below hands it to the app and the store forgets it when the app's handler has returned. The off-schedule
/// sheet is the screen's own: a day picked there arrives as an ordinary route.
public struct TodayRoot: View {
    @State private var store: TodayStore
    @Environment(\.scenePhase) private var scenePhase
    private let onRoute: @MainActor (TodayRoute) -> Void
    private let onTitleLongPress: () -> Void

    public init(
        onRoute: @escaping @MainActor (TodayRoute) -> Void,
        onTitleLongPress: @escaping () -> Void = {}
    ) {
        self.init(store: TodayStore(), onRoute: onRoute, onTitleLongPress: onTitleLongPress)
    }

    /// For the tests, which keep the store to read what it shows. `@State` keeps the first store it is given: a
    /// store does no work when it is made.
    init(
        store: TodayStore,
        onRoute: @escaping @MainActor (TodayRoute) -> Void,
        onTitleLongPress: @escaping () -> Void = {}
    ) {
        _store = State(initialValue: store)
        self.onRoute = onRoute
        self.onTitleLongPress = onTitleLongPress
    }

    public var body: some View {
        TodayScreen(state: store.state, onRoute: store.send, onTitleLongPress: onTitleLongPress)
            .task(id: scenePhase) {
                await store.run()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
    }
}
