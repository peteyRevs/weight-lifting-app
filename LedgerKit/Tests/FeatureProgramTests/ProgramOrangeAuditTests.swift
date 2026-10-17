#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F11 S9, criterion 8 (Pete's decision 1, A): where the accent is on each screen, by the colour of the
    /// pixels each part draws, in both themes.
    ///
    /// - **Builder:** a deload week's "DELOAD" under its chip while another week is selected; the title "WEEK 8
    ///   · DELOAD" while the deload week is the selected one (its chip is then filled with ink, where orange
    ///   would be below AA). Nothing else: not the name, the strip, the week's actions, "Deload" switched on,
    ///   the days, or a notice.
    /// - **Exercise library:** the foot's button while an exercise is picked. Nothing else: not the title, the
    ///   search field, a selected chip, a picked row, "already in this day", or the disabled foot.
    @Suite("Program orange audit", .serialized, .tags(.feature))
    struct ProgramOrangeAuditTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        @Test("With another week selected, the deload week's chip is the builder's only orange", arguments: themes)
        func builder_orangeIsTheDeloadChip(_ theme: ColorScheme) throws {
            let model = try ProgramPreview.builder.builderModel()
            #expect(try ProgramDrawing.orangePixels(in: ProgramHeader(model: model.header) { _ in }, theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: WeekSection(model: model.week) { _ in }, theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: TrainingDaysSection(model: model.days) { _ in }, theme) == 0)
            let block = BlockSection(model: model.block, notice: nil) { _ in }
            #expect(try ProgramDrawing.orangePixels(in: block, theme) > 0, "DELOAD under W8")
            // The chips without the deload week's draw none: the orange is that chip's.
            let others = WeekChips(chips: model.block.chips.filter { !$0.isDeload }) { _ in }
            #expect(model.block.chips.count { $0.isDeload } == 1)
            #expect(try ProgramDrawing.orangePixels(in: others, theme) == 0)
        }

        @Test("With the deload week selected, its title is the builder's only orange", arguments: themes)
        func deloadWeek_orangeIsTheWeeksTitle(_ theme: ColorScheme) throws {
            let model = try ProgramPreview.deloadWeek.builderModel()
            let block = BlockSection(model: model.block, notice: nil) { _ in }
            #expect(try ProgramDrawing.orangePixels(in: block, theme) == 0, "the selected chip is ink")
            #expect(try ProgramDrawing.orangePixels(in: WeekSection(model: model.week) { _ in }, theme) > 0)
            // Not the strip and not "Deload", switched on: the title.
            #expect(try ProgramDrawing.orangePixels(in: ScheduleStrip(cells: model.week.cells) { _ in }, theme) == 0)
            #expect(model.week.deload.isOn)
            let deload = PillButton(model.week.deload.title, style: .filled) {}
            #expect(try ProgramDrawing.orangePixels(in: deload, theme) == 0)
            let title = SectionLine(eyebrow: model.week.title, tint: .accent, note: model.week.hint)
            #expect(try ProgramDrawing.orangePixels(in: title, theme) > 0)
        }

        @Test("A notice is not orange, and a block with no deload week draws none", arguments: themes)
        func notices_areNotOrange(_ theme: ColorScheme) throws {
            #expect(try ProgramDrawing.orangePixels(in: ProgramParts(preview: .twoWeeks), theme) == 0)
            let emptyDay = try ProgramPreview.emptyDay.builderModel()
            let notice = BlockSection(model: emptyDay.block, notice: emptyDay.notice) { _ in }
            let plain = BlockSection(model: emptyDay.block, notice: nil) { _ in }
            #expect(emptyDay.notice != nil)
            #expect(try ProgramDrawing.orangePixels(in: notice, theme) == ProgramDrawing.orangePixels(in: plain, theme))
        }

        @Test("The library's only orange is its foot's button while an exercise is picked", arguments: themes)
        func library_orangeIsTheFootWithPicks(_ theme: ColorScheme) throws {
            #expect(try ProgramDrawing.orangePixels(in: ProgramParts(preview: .library), theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: ProgramParts(preview: .libraryNothing), theme) == 0)
            let picked = try ProgramPreview.libraryPicked.libraryModel()
            #expect(try ProgramDrawing.orangePixels(in: ExercisePickerPage(model: picked) { _ in }, theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: ExerciseSearchField(model: picked.search) { _ in }, theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: ExercisePickerFoot(model: picked.foot) { _ in }, theme) > 1000)
        }

        @Test("The count sees both accents and no ink", arguments: themes)
        func count_seesTheAccentAndNoInk(_ theme: ColorScheme) throws {
            #expect(try ProgramDrawing.orangePixels(in: Eyebrow("DELOAD", tint: .accent), theme) > 0)
            #expect(try ProgramDrawing.orangePixels(in: Eyebrow("DELOAD"), theme) == 0)
            #expect(try ProgramDrawing.orangePixels(in: PrimaryButton("Add 3 exercises") {}, theme) > 1000)
            #expect(try ProgramDrawing.orangePixels(in: PrimaryButton("Add 3 exercises") {}.disabled(true), theme) == 0)
        }
    }
#endif
