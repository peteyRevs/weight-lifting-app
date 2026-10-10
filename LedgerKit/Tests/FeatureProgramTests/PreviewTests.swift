#if DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureProgram is a case of `ProgramPreview`, and every case renders (the convention
    /// F07's criterion 8 set for each module with previews). The cases are the states of S9's criterion 5.
    @Suite("Previews (FeatureProgram)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureProgram is a ProgramPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureProgram")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(ProgramPreview.allCases.map(\.rawValue)))
            #expect(PreviewScan.registeredModules.contains("FeatureProgram"))
        }

        @Test("Every preview renders", arguments: ProgramPreview.allCases)
        func preview_renders(_ preview: ProgramPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every case is a state of the builder or of the library, and the two lists hold every case once")
        func cases_areSplitBetweenTheTwoScreens() throws {
            #expect(ProgramPreview.builders + ProgramPreview.libraries == ProgramPreview.allCases)
            for preview in ProgramPreview.builders {
                _ = try preview.builderModel()
            }
            for preview in ProgramPreview.libraries {
                _ = try preview.libraryModel()
            }
        }

        @Test("Every builder preview shows the state it is named for")
        func builderPreviews_showTheirStates() throws {
            let builder = try ProgramPreview.builder.builderModel()
            #expect(builder.block.title == "BLOCK · 8 WEEKS")
            #expect(builder.week.title == "WEEK 1")
            #expect(builder.notice == nil)
            #expect(builder.days.cards.count == 4)

            let deload = try ProgramPreview.deloadWeek.builderModel()
            #expect(deload.week.title == "WEEK 8 · DELOAD")
            #expect(deload.week.deload.isOn)
            #expect(deload.week.applyToLater == nil)

            let emptyDay = try ProgramPreview.emptyDay.builderModel()
            #expect(emptyDay.days.cards.last?.meta == "No exercises yet")
            #expect(emptyDay.notice == "Add at least one exercise before scheduling this day.")
            #expect(emptyDay.week.cells.first { $0.weekday == .tuesday }?.label == "D5")

            let twoWeeks = try ProgramPreview.twoWeeks.builderModel()
            #expect(twoWeeks.block.title == "BLOCK · 2 WEEKS")
            #expect(twoWeeks.notice == "A block needs at least 2 weeks.")

            let sixteen = try ProgramPreview.sixteenWeeks.builderModel()
            #expect(sixteen.block.chips.count == 16)
            #expect(sixteen.header.name == ProgramPreviewData.longName)
        }

        @Test("Every library preview shows the state it is named for")
        func libraryPreviews_showTheirStates() throws {
            let library = try ProgramPreview.library.libraryModel()
            #expect(library.rows.count == 8)
            #expect(library.rows.count { $0.inDayMark != nil } == 1)
            #expect(library.foot.action == nil)
            #expect(library.muscles.selected == ["Back"] && library.equipment.selected == ["Cable"])

            let picked = try ProgramPreview.libraryPicked.libraryModel()
            #expect(picked.rows.filter(\.isPicked).compactMap(\.pickMark) == ["3", "1", "2"])
            #expect(picked.foot.title == "Add 3 exercises")

            let nothing = try ProgramPreview.libraryNothing.libraryModel()
            #expect(nothing.empty?.message == "Nothing matches that filter.")
            #expect(nothing.search.query == "zzz")
        }
    }
#endif
