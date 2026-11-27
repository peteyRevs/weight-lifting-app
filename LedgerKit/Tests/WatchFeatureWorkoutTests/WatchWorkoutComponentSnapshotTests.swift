import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S4: the set screen's components against their references, on the watch's black. A trimmed matrix (orchestrator
/// ruling: 20 new references at most): 46 mm at its default text size, the design's own, and 42 mm at AX3, the
/// narrowest screen at the largest text, where a wide weight must still fit; the dots, which hold no text, at 46 mm
/// only. 49 mm and 42 mm at its default size are left to the screens' snapshots (F18 S5). Recorded on the PR-Watch
/// simulator (Apple Watch Series 12 46 mm), which renders every case size as a fixed layout.
@MainActor
@Suite("Watch component snapshots", .tags(.watch), .serialized)
struct WatchWorkoutComponentSnapshotTests {
    nonisolated static let trimmed = [
        WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize), WatchAppearance(.mm42, .accessibility3)
    ]

    @Test("CrownWeight at three and four digits and in kilograms matches its references", arguments: trimmed)
    func crownWeight_matchesReference(_ appearance: WatchAppearance) {
        #expect(CrownWeightGallery.dials.count == 3)
        assertWatchSnapshot(of: CrownWeightGallery().ledgerWatchPage(), appearance)
    }

    @Test("SetDots, none to all logged and with the wrist down, match their reference (46 mm)")
    func setDots_matchesReference() {
        assertWatchSnapshot(of: SetDotsGallery().ledgerWatchPage(), Self.trimmed[0])
    }

    @Test("HeartRateLine with a reading and with \"— BPM\" matches its references", arguments: trimmed)
    func heartRateLine_matchesReference(_ appearance: WatchAppearance) {
        assertWatchSnapshot(of: HeartRateLineGallery().ledgerWatchPage(), appearance)
    }
}
