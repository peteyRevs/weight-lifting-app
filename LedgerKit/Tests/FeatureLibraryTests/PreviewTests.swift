#if DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureLibrary is a case of `LibraryPreview`, and every case renders (the convention
    /// F07's criterion 8 set for each module with previews).
    @Suite("Previews (FeatureLibrary)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureLibrary is a LibraryPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureLibrary")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(LibraryPreview.allCases.map(\.rawValue)))
            #expect(PreviewScan.registeredModules.contains("FeatureLibrary"))
        }

        @Test("Every preview renders", arguments: LibraryPreview.allCases)
        func preview_renders(_ preview: LibraryPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every preview shows the state it is named for")
        func previews_showTheirStates() throws {
            let populated = try LibraryPreview.populated.model()
            #expect(populated.section(.recent)?.rows.count == 5)
            #expect(populated.row(LibraryPreviewData.customName)?.meta == "Barbell · Chest · Custom")
            #expect(populated.section(.recent)?.rows.allSatisfy { $0.record != "—" } == true)

            #expect(try LibraryPreview.filtered.model().names(.all) == ["Chest-Supported Row"])
            let nothing = try LibraryPreview.emptySearch.model()
            #expect(nothing.sections.isEmpty && nothing.search.query == "zzz")

            let noHistory = try LibraryPreview.noHistory.model()
            #expect(noHistory.sections.map(\.id) == [.all])

            let none = try LibraryPreview.noExercises.model()
            #expect(none.search.placeholder == "Search 0 exercises")
            #expect(none.sections.isEmpty)
        }
    }
#endif
