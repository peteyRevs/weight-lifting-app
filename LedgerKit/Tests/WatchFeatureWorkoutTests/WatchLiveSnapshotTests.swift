import LedgerDesign
import LedgerSnapshotTesting
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S5b: set ready and the rest screen against their references, on the watch's black, time standing still at
/// `Fixtures.now` (criteria 2–7 and 12). A trimmed matrix (orchestrator ruling: 20 new references at most): each state
/// at 46 mm and its default text size, filling the screen as the watch shows it; set ready and the rest with the
/// wrist down (Always-On: the orange dimmed, the heart rate hidden in its place); and both at 42 mm in AX3, the
/// narrowest screen at the largest text, drawn whole at their own height, as they scroll. Recorded on the PR-Watch
/// simulator (Apple Watch Series 12 46 mm).
@MainActor
@Suite("Watch set ready and rest snapshots", .tags(.watch), .serialized)
struct WatchLiveSnapshotTests {
    nonisolated static let states: [LiveSample] = LiveSample.allCases
    nonisolated static let wristDown: [LiveSample] = [.ready, .rest]

    static let mm46 = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)

    @Test("Each state of set ready and the rest matches its reference (46 mm)", arguments: states)
    func live_matchesReference(_ sample: LiveSample) {
        #expect(sample.readyModel != nil || sample.restModel != nil)
        assertWatchSnapshot(
            of: sample.screen.frame(height: WatchSize.mm46.size.height),
            Self.mm46,
            named: "\(sample).\(Self.mm46)"
        )
    }

    @Test("Set ready and the rest with the wrist down match their references (46 mm, Always-On)", arguments: wristDown)
    func live_wristDown_matchesReference(_ sample: LiveSample) {
        assertWatchSnapshot(
            of: sample.screen.frame(height: WatchSize.mm46.size.height).environment(\.isLuminanceReduced, true),
            Self.mm46,
            named: "\(sample).alwaysOn.\(Self.mm46)"
        )
    }

    @Test("Set ready and the rest at 42 mm in the largest text match their references, whole", arguments: wristDown)
    func live_largestText_matchesReference(_ sample: LiveSample) throws {
        let appearance = WatchAppearance(.mm42, .accessibility3)
        try assertWatchSnapshot(of: Self.page(sample), appearance, named: "\(sample).\(appearance)")
    }

    /// The screen's whole page, at its own height, as it scrolls.
    static func page(_ sample: LiveSample) throws -> some View {
        let ready = sample.readyModel.map { WatchReadyScreen(model: $0, dial: sample.dial, send: { _ in }).page }
        let rest = sample.restModel.map { WatchRestScreen(model: $0, send: { _ in }).page }
        return try (rest.map { AnyView($0) } ?? AnyView(#require(ready)))
            .background(LedgerColor.watchGround)
            .environment(\.watchTimeline, .fixed(at: Fixtures.now))
    }
}
