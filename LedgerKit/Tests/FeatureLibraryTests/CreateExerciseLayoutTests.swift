#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S3, by measurement, as `LibraryLayoutTests` measures the Library: at every text size, with Bold Text and
    /// laid out right to left (`LibraryLayoutTests.Setting.all`, through `TestSweep`), every stop of every state of
    /// the exercise sheet has a size, stands inside the page, is over no other stop and, when it can be tapped, is a
    /// 44 pt target. The eleven muscle chips wrap onto many lines at the largest sizes (risk R4).
    @Suite("Exercise sheet layout", .serialized, .tags(.feature))
    struct CreateExerciseLayoutTests {
        typealias Setting = LibraryLayoutTests.Setting

        @Test(
            "In every state and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: CreatePreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: CreatePreview, _ setting: Setting) {
            let stops = LibraryLayoutTests.placed(CreateParts(preview), setting)
            #expect(stops.count >= 40, "the parts were not read")
            let faults = LibraryLayoutTests.faults(in: stops.map { item in
                // A switch is a target too.
                item.stop.kind == .toggle
                    ? PlacedStop(stop: .button(item.stop.label), frame: item.frame) : item
            })
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "The title keeps its line beside Cancel, and Cancel stands under it at accessibility sizes",
            arguments: Setting.all
        )
        func header_titleAndCancel(_ setting: Setting) throws {
            let stops = LibraryLayoutTests.placed(CreateParts(.edit), setting)
            let title = try #require(stops.first { $0.stop == .heading("Edit exercise") }).frame
            let cancel = try #require(stops.first { $0.stop == .button("Cancel") }).frame
            if setting.size.isAccessibilitySize {
                #expect(cancel.minY >= title.maxY - 0.5, "Cancel stands under the title")
            } else {
                #expect(cancel.midY > title.minY && cancel.midY < title.maxY, "Cancel stands beside the title")
            }
        }
    }
#endif
