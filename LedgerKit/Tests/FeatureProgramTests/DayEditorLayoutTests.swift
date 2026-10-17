#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, criterion 11 and ruling 15, by measurement. That no stop is empty, outside the page, under
    /// 44 pt or over another is `ProgramViewsLayoutTests`' (four sizes, Bold Text, right to left) and the S9
    /// tester's `previews_layOutSoundly` (twelve sizes, two widths): both draw every state of the preview
    /// registry, the Day editor's seven among them. Here is what a frame cannot show, a word cut short
    /// inside its frame, and how the Day editor's blocks stand.
    ///
    /// **Cut words.** Each part of the screen is drawn alone twice, as wide as the page gives it and far
    /// wider than its words need, and the ink of the two drawings is weighed. The words are the same and
    /// only their lines differ, so the two weigh the same unless the narrow one lost words to an ellipsis.
    /// Measured on this slice's views: the same small words weigh within 4 % of each other however they
    /// wrap, a long exercise name on one line loses 25 %, and a stepper squeezed to one short line 17 %.
    ///
    /// **The day's name** is measured by itself, in a `NameField` alone, under each of the seed program's
    /// four day names and the previews' long one: the same name weighs within 4 % however it wraps, and the
    /// two letters a one-line field lost to "Lower A — Squat foc…" at `.xLarge` on 375 pt were 10 % of the
    /// name's weight (`measure_seesACut`).
    ///
    /// Swept over the twelve text sizes, an iPhone 17's width and 375 pt, plain and with Bold Text, for the
    /// bar, the names and the page with the most parts; right to left at four of the sizes (mirroring a
    /// layout breaks no line differently); the open exercise of three more states at four sizes. A part is
    /// drawn wide once for each size, weight and direction, not once for each width. Increase Contrast
    /// changes colours and no size: the snapshot suite draws it once.
    @Suite("Day editor layout", .serialized, .tags(.feature))
    struct DayEditorLayoutTests {
        /// Every text size; on the hosted PR runner (`TestSweep`) the four of `fewSizes` and `.xLarge`, where a
        /// seed day's name was cut on a 375 pt phone (the tester's finding F11-S10-1).
        nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases, also: [.xLarge])

        /// The sizes at which a part is drawn right to left as well, and the other states are measured.
        nonisolated static let fewSizes: Set<DynamicTypeSize> = [.xSmall, .large, .xxxLarge, .accessibility5]

        /// Wide enough for every part's words but the long day name's to stand on one line at `size`. That
        /// name, the longest line (about 1,050 pt at `.large`), wraps in its wide drawing too at the larger
        /// sizes, which loses nothing: both drawings hold every letter.
        nonisolated static func wide(at size: DynamicTypeSize) -> CGFloat {
            size.isAccessibilitySize ? 2400 : 1200
        }

        /// The weights of two drawings of the same words differ by less than this share of the wide one's:
        /// where a letter's edge falls on a pixel moves a little weight (under 4 % for the small type,
        /// measured), and a lost word moves far more.
        nonisolated static let tolerance = 0.06

        /// The red of the dark ground, #0B0B0D, and of the lightest thing that is no word: a strong hairline
        /// on it is 44.
        nonisolated static let ground = 11
        nonisolated static let lightestRule = 48

        /// One part of the screen, a view of the product by itself, named for a failure's line.
        struct Part {
            let name: String
            let view: AnyView
            /// Whether the part pads itself to the screen's inset, as the bar and the page do; the others
            /// are given the width the page's padding leaves them.
            var padsItself = false

            init(_ name: String, _ view: some View, padsItself: Bool = false) {
                self.name = name
                self.view = AnyView(view)
                self.padsItself = padsItself
            }
        }

        /// How much word `view` draws when it is `width` wide, in the dark theme: over the pixels lighter
        /// than a rule, how much lighter each is than the ground. A letter's soft edge weighs what it covers,
        /// so the same words weigh the same wherever their letters fall, and words cut short weigh less. The
        /// rules and the outlines, which grow with the width, weigh nothing.
        static func ink(of view: some View, _ setting: ViewsSetting, width: CGFloat) throws -> Int {
            let drawn = view
                .environment(\.dynamicTypeSize, setting.size)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
            return try ProgramDrawing.pixels(of: drawn, .dark, width: width).pixels
                .reduce(0) { $0 + (Int($1.red) > lightestRule ? Int($1.red) - ground : 0) }
        }

        /// The seed program's four day names and the previews' long one.
        static func dayNames() throws -> [String] {
            try Fixtures.seedProgram().days.map(\.name) + [ProgramPreviewData.longDayName]
        }

        /// The pinned bar, and the day's name by itself under each of `dayNames()`.
        static func barAndNames() throws -> [Part] {
            let header = try ProgramPreview.dayEditor.dayEditorModel().header
            return try [Part("bar", DayEditorBar(model: header) { _ in }, padsItself: true)] + dayNames().map {
                Part("name \($0)", NameField(label: header.nameLabel, name: $0) { _ in })
            }
        }

        /// The open exercise's row and the parts of its panel: the actions, the week line, the steppers, the
        /// progression, the switch and the strip.
        static func openParts(of model: DayEditorModel.Content) -> [Part] {
            guard let row = model.openRow, let panel = row.panel else {
                return []
            }
            let actions = SlotEditorModel(
                details: nil, supersetActions: panel.supersetActions, moveUp: panel.moveUp,
                moveDown: panel.moveDown, remove: panel.remove
            )
            var parts = [
                Part("row \(row.index)", ExerciseRow(row: row.withoutItsPanel) { _ in }),
                Part("actions", SlotPanel(panel: actions) { _ in })
            ]
            guard let details = panel.details else {
                return parts
            }
            parts.append(Part("week line", WeekPrescription(week: details.week)))
            parts += details.fields.map { Part("stepper \($0.spokenLabel)", SlotStepper(field: $0) { _ in }) }
            parts.append(Part("progression", ProgressionChips(model: details.progression) { _ in }))
            parts.append(Part("drop set", DropSetSwitch(model: details.dropSet) { _ in }))
            return parts + [Part("week strip", WeekLoads(strip: details.strip))]
        }

        /// The parts of a page: the header with the two buttons of the foot (the page of a day with no
        /// exercise), a superset's heading, every closed row, and the open exercise's parts.
        static func parts(of model: DayEditorModel.Content) -> [Part] {
            let noExercise = DayEditorModel.Content(
                id: model.id, header: model.header, groups: [], addExercise: model.addExercise,
                deleteDay: model.deleteDay
            )
            var parts = [Part("header, add and delete", DayEditorPage(model: noExercise) { _ in }, padsItself: true)]
            for group in model.groups {
                if group.header != nil {
                    let heading = DayEditorModel.Group(header: group.header, rows: [])
                    parts.append(Part("superset heading", ExerciseGroup(group: heading) { _ in }))
                }
                parts += group.rows.filter { !$0.isOpen }.map { Part("row \($0.index)", ExerciseRow(row: $0) { _ in }) }
            }
            return parts + openParts(of: model)
        }

        /// The parts of `parts` that weigh other at the page's width than drawn wide, at `size`, on both
        /// widths, plain and with Bold Text, and, where `mirrored`, at `fewSizes` right to left too; a line
        /// each.
        static func cut(_ parts: [Part], at size: DynamicTypeSize, mirrored: Bool = true) throws -> [String] {
            var styles = [ViewsSetting(size: size), ViewsSetting(size: size, isBold: true)]
            if mirrored, fewSizes.contains(size) {
                styles.append(ViewsSetting(size: size, isRightToLeft: true))
            }
            var lines: [String] = []
            for style in styles {
                for part in parts {
                    // The wide drawing is the same whatever the page's width: drawn once.
                    let whole = try ink(of: part.view, style, width: wide(at: size))
                    for width in ViewsSetting.widths {
                        var setting = style
                        setting.width = width
                        let room = width - (part.padsItself ? 0 : LedgerSpacing.screen + LedgerSpacing.screen)
                        let narrow = try ink(of: part.view, setting, width: room)
                        if whole == 0 || Double(abs(whole - narrow)) > Double(whole) * tolerance {
                            lines.append("\(setting.testDescription): \(part.name) weighs \(narrow), whole \(whole)")
                        }
                    }
                }
            }
            return lines
        }

        @Test(
            "No word of the bar, of a seed day's name, of a long name or of the page with the most parts is cut",
            arguments: sizes
        )
        func words_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let parts = try Self.barAndNames() + Self.parts(of: ProgramPreview.dayOpenDouble.dayEditorModel())
            #expect(parts.count == 24, "the bar, five names, the header and foot, a heading, four rows, twelve open")
            let lines = try Self.cut(parts, at: size)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "No word of a drop set that is on, of a superset's second exercise or of a deload week is cut",
            arguments: [ProgramPreview.dayDropSet, .daySuperset, .dayDeload], sizes.filter(fewSizes.contains)
        )
        func words_otherStates_areDrawnWhole(_ preview: ProgramPreview, _ size: DynamicTypeSize) throws {
            let parts = try Self.openParts(of: preview.dayEditorModel())
            #expect(parts.count >= 11)
            // Right to left is the page with the most parts': the same views.
            let lines = try Self.cut(parts, at: size, mirrored: false)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test("No word of a long exercise name is cut: it wraps under itself", arguments: sizes)
        func longExerciseName_isDrawnWhole(_ size: DynamicTypeSize) throws {
            let model = try ProgramPreview.dayLongNames.dayEditorModel()
            let rows = model.rows.filter { $0.name == ProgramPreviewData.longExerciseName }
                .map { Part("row \($0.index)", ExerciseRow(row: $0) { _ in }) }
            #expect(rows.count == 2, "the first exercise and the first of the superset")
            let lines = try Self.cut(rows, at: size)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test("The measure sees a word cut short and two letters lost from a name, and passes the same words wrapped")
        func measure_seesACut() throws {
            let words = ProgramPreviewData.longExerciseName
            #expect(try Self.cut([Part("wrapped", Text(verbatim: words).ledgerFont(.body))], at: .large).isEmpty)
            let oneLine = Part("cut", Text(verbatim: words).ledgerFont(.body).lineLimit(1))
            #expect(try Self.cut([oneLine], at: .large).count == 6, "two widths, plain, bold and right to left")
            // What the one-line field did to a seed day's name one step above the default size on a 375 pt
            // phone: "Lower A — Squat foc…" (the tester's finding F11-S10-1).
            let name = Part("name", Text(verbatim: "Lower A — Squat focus").ledgerFont(.title).lineLimit(1))
            let lost = try Self.cut([name], at: .xLarge)
            #expect(lost.contains { $0.hasPrefix("xLarge, 375 pt: ") }, "\(lost)")
            #expect(try Self.cut([name], at: .xSmall).isEmpty, "at the smallest size the name fits its line")
        }
    }

    // MARK: - How the blocks stand

    extension DayEditorLayoutTests {
        static func placed(_ preview: ProgramPreview, at size: DynamicTypeSize = .large) -> [PlacedStop] {
            ProgramParts(preview: preview).placedStops(SnapshotAppearance(.light, size))
        }

        static func frame(_ label: String, in stops: [PlacedStop]) throws -> CGRect {
            try #require(stops.first { $0.stop.label == label }, "no stop \(label)").frame
        }

        @Test("A superset's rows share one block under its heading; the blocks stand apart")
        func superset_rowsShareOneBlock() throws {
            let stops = Self.placed(.dayEditor)
            let third = try Self.frame("3, Chest-Supported Row", in: stops)
            let heading = try Self.frame("Superset", in: stops)
            let first = try Self.frame("4A, Lat Pulldown", in: stops)
            let second = try Self.frame("4B, Cable Lateral Raise", in: stops)
            // Only a rule stands between the two rows of the superset.
            #expect(second.minY - first.maxY < 2, "\(second.minY - first.maxY)")
            #expect(heading.minY - third.maxY >= LedgerSpacing.l, "\(heading.minY - third.maxY)")
            #expect(first.minY > heading.maxY)
            let alone = try Self.frame("2, Incline DB Press", in: stops)
            #expect(third.minY - alone.maxY >= LedgerSpacing.l, "an exercise on its own is a block of its own")
        }

        @Test("The open exercise's panel stands inside its block: under its row, above the next block")
        func panel_standsInsideItsRowsBlock() throws {
            let stops = Self.placed(.dayOpenLinear)
            let labels = stops.map(\.stop.label)
            let row = try #require(labels.firstIndex(of: "1, Barbell Bench Press"))
            let next = try #require(labels.firstIndex(of: "2, Incline DB Press"))
            #expect(
                next - row > 12,
                "the week line, five steppers, the progression, the switch, the actions, the strip"
            )
            for stop in stops[(row + 1) ..< next] {
                #expect(stop.frame.minY >= stops[row].frame.maxY - 1, "\(stop.stop)")
                #expect(stop.frame.maxY <= stops[next].frame.minY, "\(stop.stop)")
            }
        }

        @Test("The chips and the slot's actions wrap at an accessibility size, and no row scrolls sideways")
        func chipsAndActions_wrap() {
            for (size, rows) in [(DynamicTypeSize.large, 1), (.accessibility5, 2)] {
                let stops = Self.placed(.dayOpenDouble, at: size)
                let chips = stops.filter { ["Linear", "Double", "Fixed"].contains($0.stop.label) }
                let actions = stops.filter {
                    ["Superset with next", "Move up", "Move down", "Remove"].contains($0.stop.label)
                }
                #expect(chips.count == 3 && actions.count == 4)
                #expect(ProgramViewsLayoutTests.rows(of: chips).count >= rows, "\(size)")
                #expect(ProgramViewsLayoutTests.rows(of: actions).count >= rows, "\(size)")
            }
        }

        @Test("At an accessibility size a row's scheme and load stand under its texts, and the row is taller")
        func row_accessibilitySize_stacks() throws {
            let large = try Self.frame("1, Barbell Bench Press", in: Self.placed(.dayEditor))
            let larger = try Self.frame("1, Barbell Bench Press", in: Self.placed(.dayEditor, at: .accessibility3))
            #expect(larger.height > large.height * 2, "\(large.height) to \(larger.height)")
        }
    }
#endif
