#if DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureLibrary is a case of `LibraryPreview`, (F12 S2) `HistoryPreview` or (F12 S3)
    /// `CreatePreview`, and every case renders (the convention F07's criterion 8 set for each module with previews).
    @Suite("Previews (FeatureLibrary)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureLibrary is a Library, History or Create preview case, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureLibrary")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            let cases = LibraryPreview.allCases.map(\.rawValue) + HistoryPreview.allCases.map(\.rawValue)
                + CreatePreview.allCases.map(\.rawValue)
            #expect(Set(names.compactMap(\.self)) == Set(cases))
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

        @Test("Every history preview renders", arguments: HistoryPreview.allCases)
        func historyPreview_renders(_ preview: HistoryPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every history preview shows the state it is named for")
        func historyPreviews_showTheirStates() throws {
            let logged = try HistoryPreview.logged.model()
            #expect(logged.numbers.allSatisfy { $0 != nil } && logged.chart.bars.last?.isAccented == true)
            #expect(logged.log.entries.contains { $0.tag == "PR" })
            #expect(try HistoryPreview.gaps.model().numbers.map { $0 == nil } == [
                false, false, true, false, false, true, false, false
            ])
            #expect(try HistoryPreview.noData.model().chart.empty != nil)
            #expect(try HistoryPreview.kilograms.model().chart.delta?.hasSuffix(" kg") == true)
        }
    }

    @Test("Every exercise sheet preview renders", arguments: CreatePreview.allCases)
    func createPreview_renders(_ preview: CreatePreview) {
        #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
    }

    @Test("Every exercise sheet preview shows the state it is named for")
    func createPreviews_showTheirStates() {
        #expect(CreatePreview.empty.model().name.text.isEmpty)
        #expect(CreatePreview.filled.model().name.text == LibraryPreviewData.customName)
        #expect(CreatePreview.nameTaken.model().name.problem == "An exercise with that name already exists.")
        #expect(CreatePreview.saveFailed.model().foot.problem == "Couldn't save the exercise. Try again.")
        #expect(CreatePreview.edit.model().title == "Edit exercise")
    }
#endif
