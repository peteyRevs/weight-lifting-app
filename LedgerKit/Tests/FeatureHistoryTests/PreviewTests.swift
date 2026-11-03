#if DEBUG
    @testable import FeatureHistory
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureHistory is a case of `HistoryPreview` or `DetailPreview`, and every case renders
    /// (the convention F07's criterion 8 set for each module with previews).
    @Suite("Previews (FeatureHistory)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureHistory is a History or a detail preview case, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureHistory")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            let cases = HistoryPreview.allCases.map(\.rawValue) + DetailPreview.allCases.map(\.rawValue)
            #expect(Set(names.compactMap(\.self)) == Set(cases))
            #expect(PreviewScan.registeredModules.contains("FeatureHistory"))
        }

        @Test("Every preview renders", arguments: HistoryPreview.allCases)
        func preview_renders(_ preview: HistoryPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every detail preview renders", arguments: DetailPreview.allCases)
        func detailPreview_renders(_ preview: DetailPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every detail preview shows the state it is named for")
        func detailPreviews_showTheirStates() throws {
            #expect(try DetailPreview.withRecords.model().receipt.records != nil)
            #expect(try DetailPreview.noRecords.model().receipt.records == nil)
            #expect(try DetailPreview.kilograms.model().receipt.tiles.last?.label == "KG MOVED")
            #expect(try DetailPreview.withRecords.model().receipt.tiles.last?.label == "LB MOVED")
        }

        @Test("Every preview shows the state it is named for")
        func previews_showTheirStates() throws {
            let populated = try HistoryPreview.populated.model()
            #expect(populated.weeks.count == 4)
            #expect(populated.rows.contains { $0.badge != nil })
            #expect(populated.rows.allSatisfy { $0.meta.hasSuffix(" lb") })
            #expect(try HistoryPreview.kilograms.model().rows.allSatisfy { $0.meta.hasSuffix(" kg") })
            let empty = try HistoryPreview.empty.model()
            #expect(empty.weeks.isEmpty && empty.title == "History")
        }
    }
#endif
