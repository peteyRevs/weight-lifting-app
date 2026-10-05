import LedgerDesign
import SwiftUI

/// The iPhone's root (F07): it renders the composition's state, onboarding or the tab shell once the database is
/// open (`MainRoot`, F08 and F09) or product decision #29's screen, and runs the launch's asynchronous part, then
/// its retries on each return to the foreground. Its first appearance ends launch-to-first-frame (#30).
public struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Which screen `MainRoot` shows. `@State` keeps the first gate: one does no work when it is made.
    @State private var gate: RootGate
    private let composition: AppComposition

    public init(composition: AppComposition) {
        self.init(composition: composition, gate: RootGate())
    }

    /// For the tests, which hand over a gate that already has its answer: a new gate has none until an awaited
    /// read returns, so a root read as soon as it is hosted is the ground colour, whatever the database holds.
    init(composition: AppComposition, gate: RootGate) {
        self.composition = composition
        _gate = State(initialValue: gate)
    }

    /// One task runs the launch's pass and then follows the active program (`RootGate.follow`), so the gate
    /// reads nothing before the pass has returned. A change of the scene's phase starts it again: the launch
    /// retries what failed, and the gate reads the active program anew, which is also how a read that failed
    /// is tried again. SwiftUI cancels the task with the view.
    public var body: some View {
        content
            .onAppear { composition.rootAppeared() }
            .task(id: scenePhase) {
                await gate.follow(composition, in: scenePhase)
            }
    }

    @ViewBuilder private var content: some View {
        switch composition.state {
        case .ready:
            MainRoot(composition: composition, gate: gate)
        case .databaseUnavailable:
            DatabaseUnavailableView()
        case .idle:
            LedgerColor.ground.ignoresSafeArea()
        }
    }
}

/// Product decision #29's screen: the database could not be opened.
struct DatabaseUnavailableView: View {
    var body: some View {
        EmptyState(AppCopy.databaseUnavailableTitle, body: AppCopy.databaseUnavailableBody)
            .padding(.horizontal, LedgerSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LedgerColor.ground)
    }
}
