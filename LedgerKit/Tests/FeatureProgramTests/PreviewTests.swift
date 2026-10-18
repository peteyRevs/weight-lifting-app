#if DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureProgram is a case of `ProgramPreview`, and every case renders (the convention
    /// F07's criterion 8 set for each module with previews). The cases are the states of S9's criterion 5 and of
    /// S10's criterion 9.
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

        @Test("Every case is a state of one of the three screens, and the three lists hold every case once")
        func cases_areSplitBetweenTheThreeScreens() throws {
            let lists = ProgramPreview.builders + ProgramPreview.libraries + ProgramPreview.dayEditors
            #expect(lists == ProgramPreview.allCases)
            for preview in ProgramPreview.builders {
                _ = try preview.builderModel()
            }
            for preview in ProgramPreview.libraries {
                _ = try preview.libraryModel()
            }
            for preview in ProgramPreview.dayEditors {
                _ = try preview.dayEditorModel()
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

        @Test("Every Day editor preview shows the state it is named for")
        func dayEditorPreviews_showTheirStates() throws {
            let closed = try ProgramPreview.dayEditor.dayEditorModel()
            #expect(closed.header.position == "DAY 1 OF 4" && closed.header.tag == "UA")
            #expect(closed.rows.count == 5 && !closed.rows.contains(where: \.isOpen))
            #expect(closed.supersetNotes == ["2 exercises back to back · rest after B"])

            let superset = try ProgramPreview.daySuperset.dayEditorModel()
            let second = try #require(superset.openRow)
            #expect(second.index == "3B" && second.panel?.actionLine == "Break out · Move up · Remove")
            #expect(second.panel?.details?.selectedProgressions == ["Fixed"])

            let linear = try ProgramPreview.dayOpenLinear.dayEditorModel()
            let bench = try #require(linear.openRow?.panel)
            #expect(bench.details?.selectedProgressions == ["Linear"])
            #expect(bench.details?.fieldLine == "SETS 5 · REPS 5 · START LOAD 180 lb · TARGET RPE 8 · REST 2:30")
            #expect(bench.moveUp == nil, "the first exercise of the day has no Move up")

            let double = try ProgramPreview.dayOpenDouble.dayEditorModel()
            let incline = try #require(double.openRow?.panel?.details)
            #expect(incline.selectedProgressions == ["Double"])
            #expect(incline.fields.map(\.label).contains("TOP OF RANGE"))

            let drop = try ProgramPreview.dayDropSet.dayEditorModel()
            let curl = try #require(drop.openRow)
            #expect(curl.panel?.details?.dropSet.isOn == true)
            #expect(curl.panel?.supersetActions.isEmpty == true, "the last exercise, on its own")

            let deload = try ProgramPreview.dayDeload.dayEditorModel()
            #expect(deload.openRow?.panel?.details?.week.eyebrow == "WEEK 8 · DELOAD")
            #expect(deload.header.meta == "Week 8 · 5 exercises · 13 sets · ~29 min")

            let long = try ProgramPreview.dayLongNames.dayEditorModel()
            #expect(long.header.name == ProgramPreviewData.longDayName)
            #expect(long.rows.map(\.name).filter { $0 == ProgramPreviewData.longExerciseName }.count == 2)
        }

        @Test("Every library preview shows the state it is named for")
        func libraryPreviews_showTheirStates() throws {
            let library = try ProgramPreview.library.libraryModel()
            #expect(library.rows.count == 8)
            #expect(library.rows.count(where: \.isMarkedInDay) == 1)
            #expect(library.foot.action == nil)
            #expect(library.muscles.selected == ["Back"] && library.equipment.selected == ["Cable"])

            let picked = try ProgramPreview.libraryPicked.libraryModel()
            #expect(picked.rows.filter(\.isPicked).count == 3)
            #expect(picked.foot.title == "Add 3 exercises")

            let nothing = try ProgramPreview.libraryNothing.libraryModel()
            #expect(nothing.empty?.message == "Nothing matches that filter.")
            #expect(nothing.search.query == "zzz")
        }
    }
#endif
