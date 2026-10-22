#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S2, N12, by measurement, as `LibraryLayoutTests`: in every history and setting no stop is empty,
    /// outside the page, under 44 points when it can be tapped, or over another; the stats stack at accessibility
    /// sizes, and stand side by side below them. The settings are the Library's (`TestSweep`, ruling R6).
    @Suite("Exercise history layout", .serialized, .tags(.feature))
    struct ExerciseHistoryLayoutTests {
        typealias Setting = LibraryLayoutTests.Setting

        @Test(
            "In every history and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: HistoryPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: HistoryPreview, _ setting: Setting) {
            let stops = LibraryLayoutTests.placed(HistoryParts(preview: preview), setting)
            #expect(stops.count >= 8, "the parts were not read")
            let faults = LibraryLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test("N12. The stats stand side by side, and stack at accessibility sizes", arguments: Setting.all)
        func stats_stackAtAccessibilitySizes(_ setting: Setting) throws {
            let model = try HistoryPreview.logged.model()
            let captions = model.stats.map(\.caption)
            let frames = LibraryLayoutTests.placed(HistoryParts(preview: .logged), setting)
                .filter { stop in captions.contains { stop.stop.label.hasSuffix(", \($0)") } }.map(\.frame)
            try #require(frames.count == 3)
            let stacked = frames[1].minY >= frames[0].maxY - 0.5 && frames[2].minY >= frames[1].maxY - 0.5
            #expect(stacked == setting.size.isAccessibilitySize, "\(frames)")
        }
    }
#endif
