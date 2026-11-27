import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S6b: the end overlay against its references, on the watch's black (criterion 10). With sets logged it offers
/// "Save workout" and no "Discard"; with nothing logged, "Discard" alone (orchestrator ruling 7). Each at 46 mm and
/// its default text size; with sets logged, with the wrist down (the orange dimmed) and at 42 mm in AX3, drawn whole
/// at its own height, as it scrolls. Recorded on the PR-Watch simulator (46 mm).
@MainActor
@Suite("Watch end overlay snapshots", .tags(.watch), .serialized)
struct WatchEndSnapshotTests {
    nonisolated static let samples: [EndSample] = EndSample.allCases

    static let mm46 = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)

    static func filling(_ view: some View) -> some View {
        view.frame(height: WatchSize.mm46.size.height)
    }

    @Test("Each end overlay matches its reference (46 mm)", arguments: samples)
    func end_matchesReference(_ sample: EndSample) {
        #expect(sample.model != nil)
        assertWatchSnapshot(of: Self.filling(sample.screen), Self.mm46, named: "\(sample).\(Self.mm46)")
    }

    @Test("The end overlay with the wrist down matches its reference (46 mm, Always-On)")
    func end_wristDown_matchesReference() {
        assertWatchSnapshot(
            of: Self.filling(EndSample.logged.screen).environment(\.isLuminanceReduced, true),
            Self.mm46,
            named: "logged.alwaysOn.\(Self.mm46)"
        )
    }

    @Test("The end overlay at 42 mm in the largest text matches its reference, whole")
    func end_largestText_matchesReference() throws {
        let model = try #require(EndSample.logged.model)
        let page = WatchEndOverlay(model: model, send: { _ in }).page.background(LedgerColor.watchGround)
        assertWatchSnapshot(of: page, WatchAppearance(.mm42, .accessibility3))
    }
}
