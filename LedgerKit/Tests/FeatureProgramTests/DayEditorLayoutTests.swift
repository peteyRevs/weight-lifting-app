#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, criterion 11, by measurement. That no stop is empty, outside the page, under 44 pt or over
    /// another is `ProgramViewsLayoutTests`' (four sizes, Bold Text, right to left) and the S9 tester's
    /// `previews_layOutSoundly` (twelve sizes, two widths): both draw every state of the preview registry,
    /// the Day editor's seven among them. Here is what a frame cannot show, a word cut short inside its
    /// frame, and how the Day editor's blocks stand.
    ///
    /// **Cut words.** Each part of the page is drawn alone twice, as wide as the page gives it and far wider
    /// than its words need, and the ink of the two drawings is weighed. The words are the same and only
    /// their lines differ, so the two weigh the same unless the narrow one lost words to an ellipsis.
    /// Measured on this slice's views: the same words weigh within 4 % of each other however they wrap, a
    /// long name on one line loses 25 %, and a stepper squeezed to one short line 17 %. Swept over the
    /// twelve text sizes, an iPhone 17's width and 375 pt, Bold Text and right to left, for the state with
    /// the most parts; two more states at four sizes. Increase Contrast changes colours and no size: the
    /// snapshot suite draws it once.
    ///
    /// **Known limit, measured here:** the day's name is a one-line field, as the program's is. A name
    /// longer than its line ends in an ellipsis while it is not being edited, and at accessibility text
    /// sizes the seed program's own "Upper A — Push focus" is such a name (`dayName_isCutInItsOneLineField`).
    @Suite("Day editor layout", .serialized, .tags(.feature))
    struct DayEditorLayoutTests {
        nonisolated static let sizes = DynamicTypeSize.allCases

        /// Far wider than any part's words at the largest text size.
        nonisolated static let wide: CGFloat = 2400

        /// The weights of two drawings of the same words differ by less than this share of the wide one's:
        /// where a letter's edge falls on a pixel moves a little weight (under 4 %, measured), and a lost
        /// word moves far more.
        nonisolated static let tolerance = 0.06

        /// The red of the dark ground, #0B0B0D, and of the lightest thing that is no word: a strong hairline
        /// on it is 44.
        nonisolated static let ground = 11
        nonisolated static let lightestRule = 48

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

        /// Upper A's header under a name short enough for its line at every text size: what the header's
        /// other words are measured in.
        static func shortNamedHeader() throws -> AnyView {
            try AnyView(DayEditorHeader(model: DayEditorTextFieldTests.content(named: "Arms")) { _ in })
        }

        /// The parts of a page, each a view of the product by itself, named for a failure's line: a
        /// superset's heading, every row, the open exercise's week line, steppers, progression, switch,
        /// actions and strip, and the page's two buttons.
        static func parts(of model: DayEditorModel.Content) -> [(name: String, view: AnyView)] {
            var parts: [(String, AnyView)] = []
            for group in model.groups {
                if group.header != nil {
                    let heading = DayEditorModel.Group(header: group.header, rows: [])
                    parts.append(("superset heading", AnyView(ExerciseGroup(group: heading) { _ in })))
                }
                for row in group.rows {
                    parts.append(("row \(row.index)", AnyView(ExerciseRow(row: row.withoutItsPanel) { _ in })))
                    guard let panel = row.panel else {
                        continue
                    }
                    let actions = SlotEditorModel(
                        details: nil, supersetActions: panel.supersetActions, moveUp: panel.moveUp,
                        moveDown: panel.moveDown, remove: panel.remove
                    )
                    parts.append(("actions", AnyView(SlotPanel(panel: actions) { _ in })))
                    guard let details = panel.details else {
                        continue
                    }
                    parts.append(("week line", AnyView(WeekPrescription(week: details.week))))
                    parts += details.fields.map { ("stepper \($0.label)", AnyView(SlotStepper(field: $0) { _ in })) }
                    parts.append(("progression", AnyView(ProgressionChips(model: details.progression) { _ in })))
                    parts.append(("drop set", AnyView(DropSetSwitch(model: details.dropSet) { _ in })))
                    parts.append(("week strip", AnyView(WeekLoads(strip: details.strip))))
                }
            }
            let foot = DayEditorModel.Content(
                id: model.id, header: model.header, groups: [], addExercise: model.addExercise,
                deleteDay: model.deleteDay
            )
            return parts + [("add and delete", AnyView(DayEditorPage(model: foot) { _ in }))]
        }

        /// The parts of `parts` that weigh less at the page's width than drawn wide, in every setting of
        /// `size`; a line each. The header and the page pad themselves; the other parts are given the width
        /// the page's padding leaves them.
        static func cut(_ parts: [(name: String, view: AnyView)], at size: DynamicTypeSize) throws -> [String] {
            var lines: [String] = []
            for setting in ViewsSetting.sweep(size) {
                for part in parts {
                    let padsItself = part.name == "header" || part.name == "add and delete"
                    let width = setting.width - (padsItself ? 0 : LedgerSpacing.screen + LedgerSpacing.screen)
                    let narrow = try ink(of: part.view, setting, width: width)
                    let whole = try ink(of: part.view, setting, width: wide)
                    if whole == 0 || Double(abs(whole - narrow)) > Double(whole) * tolerance {
                        lines.append("\(setting.testDescription): \(part.name) weighs \(narrow), whole \(whole)")
                    }
                }
            }
            return lines
        }

        @Test("No word of the header or of the page with the most parts is cut, at any text size", arguments: sizes)
        func words_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let parts = try [("header", Self.shortNamedHeader())]
                + Self.parts(of: ProgramPreview.dayOpenDouble.dayEditorModel())
            #expect(parts.count == 19, "the header, a heading, five rows, eleven parts of the panel, the foot")
            let lines = try Self.cut(parts, at: size)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "No word of a drop set that is on, of a superset's second exercise or of a deload week is cut",
            arguments: [ProgramPreview.dayDropSet, .daySuperset, .dayDeload],
            [DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility5]
        )
        func words_otherStates_areDrawnWhole(_ preview: ProgramPreview, _ size: DynamicTypeSize) throws {
            let lines = try Self.cut(Self.parts(of: preview.dayEditorModel()), at: size)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test("No word of a long exercise name is cut: it wraps under itself", arguments: sizes)
        func longExerciseName_isDrawnWhole(_ size: DynamicTypeSize) throws {
            let model = try ProgramPreview.dayLongNames.dayEditorModel()
            let rows = Self.parts(of: model).filter { $0.name.hasPrefix("row") }
            #expect(model.rows.count { $0.name == ProgramPreviewData.longExerciseName } == 2 && rows.count == 5)
            let lines = try Self.cut(rows, at: size)
            #expect(lines.isEmpty, "\(lines.count) cut: \(lines.prefix(3).joined(separator: "; "))")
        }

        /// The limit `ProgramHeader` has (S9, open question 1): the name is a one-line field, and a field of
        /// several lines is a text view, which the hosted reader cannot read. Kept as a test so that it stays
        /// known: it fails when a name that is too long for its line is drawn whole.
        @Test("Limit: a day name longer than its line ends in an ellipsis while it is not being edited")
        func dayName_isCutInItsOneLineField() throws {
            func header(_ preview: ProgramPreview) throws -> [(name: String, view: AnyView)] {
                try [("header", AnyView(DayEditorHeader(model: preview.dayEditorModel()) { _ in }))]
            }
            #expect(try Self.cut(header(.dayEditor), at: .large).isEmpty, "the seed's name fits at the default size")
            #expect(try Self.cut(header(.dayLongNames), at: .large).count == ViewsSetting.sweep(.large).count)
            // "Upper A — Push focus" is longer than a 375 pt phone's line at the largest size of the matrix.
            let seedAtAccessibility3 = try Self.cut(header(.dayEditor), at: .accessibility3)
            #expect(seedAtAccessibility3.contains { $0.contains("375 pt") }, "\(seedAtAccessibility3)")
        }

        @Test("The measure sees a word cut short, and passes the same words wrapped")
        func measure_seesACut() throws {
            let words = ProgramPreviewData.longExerciseName
            let wrapped = [(name: "wrapped", view: AnyView(Text(verbatim: words).ledgerFont(.body)))]
            let oneLine = [(name: "cut", view: AnyView(Text(verbatim: words).ledgerFont(.body).lineLimit(1)))]
            #expect(try Self.cut(wrapped, at: .large).isEmpty)
            #expect(try Self.cut(oneLine, at: .large).count == ViewsSetting.sweep(.large).count)
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
