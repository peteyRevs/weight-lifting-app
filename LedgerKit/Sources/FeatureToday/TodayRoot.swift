import SwiftUI

/// Today in the app (F09 S5): the screen over its store. It owns the store and runs its work from its tasks,
/// so nothing outlives the view; the app hands it `onRoute`, which resolves where a tap goes (architecture §4),
/// and, in Debug builds, what a long press on the title does.
///
/// **The store's task starts again when the app comes back from the background**, and SwiftUI restarts it
/// when the tab comes back on screen. A new run keeps the model on screen and reads everything again, which
/// is how Today shows a new day, or a workout changed in History, when the lifter comes back to it. In the
/// background nothing runs: the task's id changes on the way there and on the way back and at no other
/// change of the scene's phase, so Control Centre or a system alert over the app restarts nothing. A view
/// hosted with no scene (a package test's window) is told it is in the background, and runs nothing until
/// its host says otherwise.
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
            .task(id: scenePhase == .background) {
                guard scenePhase != .background else {
                    return
                }
                await store.run()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
    }
}
