import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S6a: the summary, the session list and the takeover banner against their references, on the watch's black
/// (criteria 8 and 11, spec §9). A trimmed matrix (orchestrator ruling: 20 new references at most): each summary at
/// 46 mm and its default text size, in pounds and kilograms, with records and without; the summary with the wrist
/// down (the orange dimmed, the average heart rate hidden in its place); the summary at 42 mm in AX3, drawn whole
/// at its own height, as it scrolls; the list, whole, and set ready under the banner at 46 mm. The summary's time is
/// its model's text, and set ready's is fixed at `Fixtures.now`. Recorded on the PR-Watch simulator (46 mm).
@MainActor
@Suite("Watch list, summary and banner snapshots", .tags(.watch), .serialized)
struct WatchOverlaySnapshotTests {
    nonisolated static let summaries: [SummarySample] = SummarySample.allCases

    static let mm46 = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)

    static func filling(_ view: some View) -> some View {
        view.frame(height: WatchSize.mm46.size.height)
    }

    @Test("Each summary matches its reference (46 mm)", arguments: summaries)
    func summary_matchesReference(_ sample: SummarySample) {
        #expect(sample.model != nil)
        assertWatchSnapshot(of: Self.filling(sample.screen), Self.mm46, named: "\(sample).\(Self.mm46)")
    }

    @Test("The summary with the wrist down matches its reference (46 mm, Always-On)")
    func summary_wristDown_matchesReference() {
        assertWatchSnapshot(
            of: Self.filling(SummarySample.records.screen).environment(\.isLuminanceReduced, true),
            Self.mm46,
            named: "records.alwaysOn.\(Self.mm46)"
        )
    }

    @Test("The summary at 42 mm in the largest text matches its reference, whole")
    func summary_largestText_matchesReference() throws {
        let model = try #require(SummarySample.records.model)
        let page = WatchSummaryScreen(model: model, send: { _ in }).page.background(LedgerColor.watchGround)
        assertWatchSnapshot(of: page, WatchAppearance(.mm42, .accessibility3))
    }

    @Test("The session list matches its reference, whole (46 mm)")
    func list_matchesReference() throws {
        let model = try #require(OverlaySample.listModel)
        let page = WatchListOverlay(model: model, send: { _ in }).page.background(LedgerColor.watchGround)
        assertWatchSnapshot(of: page, Self.mm46)
    }

    @Test("Set ready under the takeover banner matches its reference (46 mm)")
    func takeover_matchesReference() {
        assertWatchSnapshot(of: Self.filling(OverlaySample.takeover), Self.mm46)
    }
}
