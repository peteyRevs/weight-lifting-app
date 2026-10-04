import LedgerDesign
import SwiftUI

/// The watch's root (F07): it renders the composition's state, Today once the database is open (a placeholder until
/// F18) or product decision #29's screen, and runs the launch's asynchronous part, then its retries on each return
/// to the foreground. Its first appearance ends launch-to-first-frame (#30).
public struct WatchRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDebugMenuShown = false
    private let composition: WatchComposition

    public init(composition: WatchComposition) {
        self.composition = composition
    }

    public var body: some View {
        content
            .onAppear { composition.rootAppeared() }
            .task(id: scenePhase) {
                await composition.resume(in: scenePhase)
            }
    }

    @ViewBuilder private var content: some View {
        switch composition.state {
        case .ready:
            TodayPlaceholder { isDebugMenuShown = true }
            #if DEBUG
                .sheet(isPresented: $isDebugMenuShown) {
                    DebugMenu { await composition.diagnostics() }
                }
            #endif
        case .databaseUnavailable:
            DatabaseUnavailableView()
        case .idle:
            LedgerColor.watchGround.ignoresSafeArea()
        }
    }
}

/// Product decision #29's screen: the database could not be opened.
struct DatabaseUnavailableView: View {
    var body: some View {
        ScrollView {
            EmptyState(
                "Can't open your data right now",
                body: "Your workouts are still on this watch. Ledger tries again when you come back to it."
            )
        }
        .background(LedgerColor.watchGround)
    }
}
