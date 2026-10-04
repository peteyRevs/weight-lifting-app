import LedgerDesign
import SwiftUI

/// The iOS root. It renders the composition's state, the placeholder until F07 S3's tab shell or product decision
/// #29's screen, and runs the launch's asynchronous part, then its retries on each return to the foreground.
public struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let composition: AppComposition

    public init(composition: AppComposition) {
        self.composition = composition
    }

    public var body: some View {
        Group {
            if composition.state == .databaseUnavailable {
                EmptyState(
                    "Can't open your data right now",
                    body: "Your workouts are still on this iPhone. Ledger tries again when you come back to it."
                )
                .padding(.horizontal, LedgerSpacing.screen)
            } else {
                Text("Ledger")
            }
        }
        .task(id: scenePhase) {
            await composition.resume(in: scenePhase)
        }
    }
}
