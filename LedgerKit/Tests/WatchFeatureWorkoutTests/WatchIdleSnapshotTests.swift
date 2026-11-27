import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S5a: the screen before a workout against its references, on the watch's black (criteria 1 and 16). A trimmed
/// matrix (orchestrator ruling: 20 new references at most): every state at 46 mm and its default text size, filling
/// the screen as the watch shows it, the logged day in kilograms too, since that line holds the volume; and today's
/// plan at 42 mm in AX3, the narrowest screen at the largest text, drawn whole at its own height, as it scrolls.
/// Recorded on the PR-Watch simulator (Apple Watch Series 12 46 mm).
@MainActor
@Suite("Watch idle snapshots", .tags(.watch), .serialized)
struct WatchIdleSnapshotTests {
    nonisolated static let states: [IdleSample] = [.plan, .restDay, .noProgram, .logged, .loggedKg]

    @Test("Each state of the screen before a workout matches its reference (46 mm)", arguments: states)
    func idle_matchesReference(_ sample: IdleSample) {
        let appearance = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)
        #expect(sample.model != nil)
        assertWatchSnapshot(
            of: sample.screen.frame(height: WatchSize.mm46.size.height),
            appearance,
            named: "\(sample).\(appearance)"
        )
    }

    @Test("Today's plan at 42 mm in the largest text matches its reference, whole")
    func idle_largestText_matchesReference() throws {
        let model = try #require(IdleSample.plan.model)
        let page = WatchIdleScreen(model: model, send: { _ in }).page.background(LedgerColor.watchGround)
        assertWatchSnapshot(of: page, WatchAppearance(.mm42, .accessibility3))
    }
}
