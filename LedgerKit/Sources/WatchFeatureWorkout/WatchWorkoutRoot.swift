import LedgerDesign
import SwiftUI

/// The watch's workout (F18): the screen of the store's mode, over the store it owns. Its task runs the store for as
/// long as the root is on screen, in every scene phase: a workout goes on with the wrist down. The app hands it the
/// app's display name, for "Open %@ on iPhone", the composition's Health session, and, in Debug builds, what a long
/// press on the title does.
///
/// The session list and the end overlay stand in the live screen's place while one is open, as the prototype draws
/// them. While another app's workout holds Health's session, its banner stands above the screen (spec §9).
public struct WatchWorkoutRoot: View {
    @State private var store: WatchWorkoutStore
    private var clockOffset: TimeInterval = 0
    private let onTitleLongPress: () -> Void

    /// - Parameters:
    ///   - appName: the app's display name (`CFBundleDisplayName`), never a literal (product decisions › Naming).
    ///   - health: the watch's Health session, which the composition runs; nil shows none.
    ///   - clockOffset: the seconds a UI test moved the app's clock by (`-LEDGER_UITEST_NOW`), which the
    ///     screens' timers follow; 0 in the app.
    public init(
        appName: String, health: WatchHealthSession?, clockOffset: TimeInterval = 0,
        onTitleLongPress: @escaping () -> Void = {}
    ) {
        self.init(store: WatchWorkoutStore(appName: appName, health: health), onTitleLongPress: onTitleLongPress)
        self.clockOffset = clockOffset
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
            .watchBanner(store.banner)
            .background(LedgerColor.watchGround)
            .transformEnvironment(\.watchTimeline) { [clockOffset] in $0.offset = clockOffset }
            .task { await store.run() }
    }

    @ViewBuilder private var content: some View {
        switch Self.screen(of: store) {
        case .waiting:
            LedgerColor.watchGround
        case let .idle(model):
            WatchIdleScreen(model: model, send: store.send, onTitleLongPress: onTitleLongPress)
        case let .ready(model):
            WatchReadyScreen(model: model, dial: store.crownDial, send: store.send)
        case let .rest(model):
            WatchRestScreen(model: model, send: store.send)
        case let .list(model):
            WatchListOverlay(model: model, send: store.send)
        case let .end(model):
            WatchEndOverlay(model: model, send: store.send)
        case let .summary(model):
            WatchSummaryScreen(model: model, send: store.send)
        }
    }
}

extension WatchWorkoutRoot {
    /// The screen the root shows: the open session list or end overlay, or its mode's, drawn from that mode's model.
    /// The rest and "GO" share the rest screen.
    enum Screen: Equatable {
        /// The store has not heard what it needs for the mode yet: the black ground alone.
        case waiting
        case idle(WatchIdleModel)
        case ready(WatchReadyModel)
        case rest(WatchRestModel)
        case list(WatchListModel)
        case end(WatchEndModel)
        case summary(WatchSummaryModel)
    }

    static func screen(of store: WatchWorkoutStore) -> Screen {
        let overlay: Screen? = switch store.shownOverlay {
        case .list: store.list.map(Screen.list)
        case .end: store.end.map(Screen.end)
        case nil: nil
        }
        if let overlay {
            return overlay
        }
        let screen: Screen? = switch store.mode {
        case .idle: store.idle.map(Screen.idle)
        case .ready: store.ready.map(Screen.ready)
        case .rest, .restOver: store.rest.map(Screen.rest)
        case .summary: store.summary.map(Screen.summary)
        }
        return screen ?? .waiting
    }
}
