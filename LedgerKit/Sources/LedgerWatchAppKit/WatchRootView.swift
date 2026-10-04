import LedgerDesign
import SwiftUI

/// The watch root. It renders the composition's state, the placeholder until F07 S3's watch shell or product
/// decision #29's screen, and runs the launch's asynchronous part, then its retries on each return to the
/// foreground.
public struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let composition: WatchComposition

    public init(composition: WatchComposition) {
        self.composition = composition
    }

    public var body: some View {
        Group {
            if composition.state == .databaseUnavailable {
                ScrollView {
                    EmptyState(
                        "Can't open your data right now",
                        body: "Your workouts are still on this watch. Ledger tries again when you come back to it."
                    )
                }
            } else {
                Text("Ledger")
            }
        }
        .task(id: scenePhase) {
            await composition.resume(in: scenePhase)
        }
    }
}
