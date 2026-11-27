import LedgerDesign
import SwiftUI

/// The watch's workout (F18): the screen of the store's mode, over the store it owns. Its task runs the store for as
/// long as the root is on screen, in every scene phase: a workout goes on with the wrist down. The app hands it the
/// app's display name, for "Open %@ on iPhone", the composition's Health session, and, in Debug builds, what a long
/// press on the title does.
///
/// The screen before a workout is drawn here; set ready, the rest screen and the summary are stubs until F18 S5b and
/// S6 (`WatchStubScreen`), and the overlays come with S6.
public struct WatchWorkoutRoot: View {
    @State private var store: WatchWorkoutStore
    private let onTitleLongPress: () -> Void

    /// - Parameters:
    ///   - appName: the app's display name (`CFBundleDisplayName`), never a literal (product decisions › Naming).
    ///   - health: the watch's Health session, which the composition runs; nil shows none.
    public init(appName: String, health: WatchHealthSession?, onTitleLongPress: @escaping () -> Void = {}) {
        self.init(store: WatchWorkoutStore(appName: appName, health: health), onTitleLongPress: onTitleLongPress)
    }

    /// For the tests, which keep the store to drive it. `@State` keeps the first store it is given: a store does no
    /// work when it is made.
    init(store: WatchWorkoutStore, onTitleLongPress: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.onTitleLongPress = onTitleLongPress
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LedgerColor.watchGround)
            .task { await store.run() }
    }

    @ViewBuilder private var content: some View {
        switch Self.screen(of: store) {
        case .waiting:
            LedgerColor.watchGround
        case let .idle(model):
            WatchIdleScreen(model: model, send: store.send, onTitleLongPress: onTitleLongPress)
        case let .ready(model):
            WatchStubScreen(lines: [model.setLabel, model.exerciseName])
        case let .rest(model):
            WatchStubScreen(lines: [model.title, model.clock])
        case let .summary(model):
            WatchStubScreen(lines: [model.title], pill: (model.done, .dismissSummary), send: store.send)
        }
    }
}

extension WatchWorkoutRoot {
    /// The screen the root shows: its mode's, drawn from that mode's model. The rest and "GO" share the rest screen.
    enum Screen: Equatable {
        /// The store has not heard what it needs for the mode yet: the black ground alone.
        case waiting
        case idle(WatchIdleModel)
        case ready(WatchReadyModel)
        case rest(WatchRestModel)
        case summary(WatchSummaryModel)
    }

    static func screen(of store: WatchWorkoutStore) -> Screen {
        let screen: Screen? = switch store.mode {
        case .idle: store.idle.map(Screen.idle)
        case .ready: store.ready.map(Screen.ready)
        case .rest, .restOver: store.rest.map(Screen.rest)
        case .summary: store.summary.map(Screen.summary)
        }
        return screen ?? .waiting
    }
}
