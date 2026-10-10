#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F11 S10, criterion 8 (Pete's decision 1, A): where the accent is on the Day editor, by the colour of the
    /// pixels each part draws, in both themes.
    ///
    /// **The one orange thing:** the open exercise's week eyebrow, whole, while the shown week is a deload
    /// week ("WEEK 8 · DELOAD") or holds its load after a missed week ("WEEK 4 · HELD"); `WeekLine.isDeload`
    /// and `isHeld` pick it, never the eyebrow's words. Nothing else: not "SUPERSET", an open row's scheme or
    /// caret, the chosen progression, the drop set's switch when on, "Remove", "Delete day", nor the deload
    /// and held entries of the week strip (the shown week's entry is ink, the others grey).
    @Suite("Day editor orange audit", .serialized, .tags(.feature))
    struct DayEditorOrangeAuditTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        static func orange(_ view: some View, _ theme: ColorScheme) throws -> Int {
            try ProgramDrawing.orangePixels(in: view, theme)
        }

        /// The details of the open exercise of a model.
        static func details(of model: DayEditorModel.Content) throws -> SlotEditorModel.Details {
            try #require(model.openRow?.panel?.details)
        }

        static func details(
            _ details: SlotEditorModel.Details,
            week: SlotEditorModel.WeekLine
        ) -> SlotEditorModel.Details {
            SlotEditorModel.Details(
                week: week, fields: details.fields, progression: details.progression, dropSet: details.dropSet,
                strip: details.strip
            )
        }

        @Test("In a week that is no deload and holds nothing, no state of the Day editor is orange", arguments: themes)
        func plainWeek_drawsNoOrange(_ theme: ColorScheme) throws {
            let plain: [ProgramPreview] = [
                .dayEditor, .daySuperset, .dayOpenLinear, .dayOpenDouble, .dayDropSet, .dayLongNames
            ]
            for preview in plain {
                #expect(try Self.orange(ProgramParts(preview: preview), theme) == 0, "\(preview.rawValue)")
            }
            // The drop set is on in one of them, a progression chosen in four, a superset in all.
            #expect(try Self.details(of: ProgramPreview.dayDropSet.dayEditorModel()).dropSet.isOn)
        }

        @Test("In a deload week the open exercise's week eyebrow is the Day editor's only orange", arguments: themes)
        func deloadWeek_orangeIsTheWeekLine(_ theme: ColorScheme) throws {
            let model = try ProgramPreview.dayDeload.dayEditorModel()
            let panel = try #require(model.openRow?.panel)
            let details = try Self.details(of: model)
            #expect(details.week.isDeload)
            #expect(try Self.orange(ProgramParts(preview: .dayDeload), theme) > 0)
            #expect(try Self.orange(DayEditorBar(model: model.header) { _ in }, theme) == 0)
            #expect(try Self.orange(DayEditorHeader(model: model) { _ in }, theme) == 0)
            for row in model.rows {
                let alone = ExerciseRow(row: row.withoutItsPanel) { _ in }
                #expect(try Self.orange(alone, theme) == 0, "\(row.index), open or closed")
            }
            #expect(try Self.orange(SlotDetails(details: details) { _ in }, theme) > 0)
            // Not the strip, whose last entry is the deload week's and whose shown entry it is too.
            #expect(details.strip.entries.last.map { $0.isDeload && $0.isShown } == true)
            #expect(try Self.orange(WeekLoads(strip: details.strip), theme) == 0)
            #expect(try Self.orange(ProgressionChips(model: details.progression) { _ in }, theme) == 0)
            // With the same panel in a week that is none, nothing of the panel is orange: the eyebrow was it.
            let week = SlotEditorModel.WeekLine(
                eyebrow: details.week.eyebrow, isDeload: false, isHeld: false, line: details.week.line
            )
            let plain = SlotEditorModel(
                details: Self.details(details, week: week), supersetActions: panel.supersetActions,
                moveUp: panel.moveUp, moveDown: panel.moveDown, remove: panel.remove
            )
            #expect(try Self.orange(SlotPanel(panel: plain) { _ in }, theme) == 0)
        }

        @Test("With every exercise closed, a deload week draws no orange", arguments: themes)
        func deloadWeek_closed_drawsNoOrange(_ theme: ColorScheme) throws {
            let input = try DayEditorFixtures.seedInput(weekIndex: 7)
            let model = try DayEditorPresentation.make(input).content()
            #expect(model.header.meta.hasPrefix("Week 8"))
            #expect(try Self.orange(DayEditorParts(model: model), theme) == 0)
        }

        @Test(
            "A week that holds its load after a missed week has an orange eyebrow too, and a grey strip",
            arguments: themes
        )
        func heldWeek_orangeIsTheWeekLine(_ theme: ColorScheme) throws {
            var input = try DayEditorFixtures.seedInput(dayIndex: ProgramFixtures.DayIndex.lowerA, weekIndex: 3)
            input.program.days[ProgramFixtures.DayIndex.lowerA].slots[0].misses = [2]
            var screen = DayScreen(input)
            try screen.open("1")
            let details = try screen.details()
            #expect(details.week.eyebrow == "WEEK 4 · HELD" && details.week.isHeld && !details.week.isDeload)
            #expect(try Self.orange(SlotDetails(details: details) { _ in }, theme) > 0)
            #expect(try Self.orange(WeekLoads(strip: details.strip), theme) == 0)
        }

        @Test("The model's facts pick the orange, not the eyebrow's words", arguments: themes)
        func facts_pickTheOrange_notTheWords(_ theme: ColorScheme) throws {
            let details = try Self.details(of: ProgramPreview.dayOpenLinear.dayEditorModel())
            func drawn(_ eyebrow: String, isDeload: Bool, isHeld: Bool) throws -> Int {
                let week = SlotEditorModel.WeekLine(
                    eyebrow: eyebrow, isDeload: isDeload, isHeld: isHeld, line: details.week.line
                )
                return try Self.orange(SlotDetails(details: Self.details(details, week: week)) { _ in }, theme)
            }
            #expect(try drawn("WEEK 8 · DELOAD", isDeload: false, isHeld: false) == 0)
            #expect(try drawn("WEEK 4 · HELD", isDeload: false, isHeld: false) == 0)
            #expect(try drawn("WEEK 3", isDeload: true, isHeld: false) > 0)
            #expect(try drawn("WEEK 3", isDeload: false, isHeld: true) > 0)
        }
    }
#endif
