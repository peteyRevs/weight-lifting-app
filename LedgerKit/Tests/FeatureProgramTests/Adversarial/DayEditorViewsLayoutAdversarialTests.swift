#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, gate G2, round 1, criteria 10 and 11 by measurement, in the states no preview draws: frames
    /// (no stop empty, outside the page, a target under 44 pt, or over another), pills cut inside their
    /// frames, and what neither a frame nor a weight of ink shows: a word broken in two across lines, the
    /// steppers' round buttons (no stop of their own), and where the day's name starts to be cut.
    ///
    /// Three sizes decide here, not twelve: the largest that keeps a row's numbers beside its name
    /// (`.xxxLarge`), the first that stacks them (`.accessibility1`) and the largest. The previews are swept
    /// at all twelve by `ProgramViewsLayoutAdversarialTests.previews_layOutSoundly`.
    @Suite("Adversarial F11 S10 · frames, pills and broken words", .serialized, .tags(.feature))
    struct DayEditorViewsLayoutAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [.xxxLarge, .accessibility1, .accessibility5]

        @Test("Each of this tester's states lays out soundly", arguments: DayViewsState.allCases, sizes)
        func states_layOutSoundly(_ state: DayViewsState, _ size: DynamicTypeSize) throws {
            let faults = try ProgramViewsLayoutAdversarialTests.faults(
                of: DayEditorParts(model: state.model()),
                at: size
            )
            #expect(faults.isEmpty, "\(faults.count) faults: \(faults.prefix(3).joined(separator: "; "))")
        }

        /// For each stop of the oracle's tree, the pill that draws it, by itself; nil for a stop that is no
        /// pill. The chosen progression is a pill too.
        static func pillsAlone(_ model: DayEditorModel.Content) -> [AnyView?] {
            let chosen = Set(model.rows.flatMap { $0.panel?.details?.progression.chips ?? [] }.filter(\.isSelected)
                .map(\.title))
            let stops = DayViewsOracle.tree(model).map(\.stop)
            return stops.enumerated().map { place, stop in
                let isAPill = place > 1 && place < stops.count - 1 && stop.disclosure == .none
                    && (stop.kind == .button || stop.isSelected)
                guard isAPill else {
                    return nil
                }
                guard chosen.contains(stop.label) else {
                    return AnyView(PillButton(stop.label) {})
                }
                // The chosen one is read as the oracle writes it: selected text, no button.
                return AnyView(
                    PillButton(stop.label, style: .filled) {}
                        .accessibilityRemoveTraits(.isButton)
                        .accessibilityAddTraits(.isStaticText)
                )
            }
        }

        @Test(
            "No chip, no slot action and no Add exercise is cut inside its pill",
            arguments: [DayViewsState.twelve, .lastOpen, .fiveDigits], sizes
        )
        func states_noPillIsCut(_ state: DayViewsState, _ size: DynamicTypeSize) throws {
            let model = try state.model()
            let alone = Self.pillsAlone(model)
            #expect(alone.count { $0 != nil } >= 6, "three chips, at least two actions, Add exercise")
            // 374 pt, not 375: the page then starts on a whole point of the 402 pt window, and a frame is
            // not a pixel narrower for where it stands (measured at 375: 129.0 pt for a pill of 129.7).
            let settings = [SnapshotConfig.phoneWidth, 374].flatMap { width in
                [false, true].map { ViewsSetting(size: size, width: width, isBold: $0) }
            }
            let cut = settings.flatMap { setting in
                ProgramViewsProbe.cut(DayEditorParts(model: model), alone: alone, setting)
                    .map { "\(setting.testDescription): \($0)" }
            }
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }
    }

    // MARK: - A word broken across two lines

    extension DayEditorViewsLayoutAdversarialTests {
        /// A closed row of Upper A under another name and load.
        static func row(named name: String, load: String) throws -> ExerciseRow {
            let seed = try #require(ProgramPreview.dayEditor.dayEditorModel().rows.first)
            let row = DayEditorModel.Row(
                id: seed.id, index: seed.index, name: name, sub: seed.sub, scheme: seed.scheme, load: load,
                hasDropSet: false, isOpen: false, spokenLabel: seed.spokenLabel, spokenValue: seed.spokenValue,
                action: seed.action, panel: nil
            )
            return ExerciseRow(row: row) { _ in }
        }

        /// How much taller, in points, a row is under `name` than under a name of one letter: 0 while the
        /// name stands on one line. A name of one word has nowhere to wrap, so when its row is taller the
        /// word was broken in two, which a weight of ink cannot show: every letter is still drawn.
        static func growth(of name: String, load: String, _ setting: ViewsSetting) throws -> CGFloat {
            func height(_ name: String) throws -> CGFloat {
                let row = try Self.row(named: name, load: load).frame(width: setting.width - 2 * LedgerSpacing.screen)
                return ProgramViewsProbe.placed(row, setting).first?.frame.height ?? 0
            }
            return try height(name) - height("X")
        }

        /// The longest single words of the bundled catalog's names are "Hyperextension" and "Concentration".
        @Test(
            "A catalog exercise's one-word name is never broken in two while the numbers stand beside it",
            arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge], ViewsSetting.widths
        )
        func oneWordName_besideItsNumbers_isNotBroken(_ size: DynamicTypeSize, _ width: CGFloat) throws {
            for isBold in [false, true] {
                let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                for (load, what) in [("180 lb", "the seed's load"), ("\(DayViewsState.load) lb", "five digits")] {
                    let growth = try Self.growth(of: "Hyperextension", load: load, setting)
                    #expect(growth < 1, "\(setting.testDescription), \(what): the row is \(growth) pt taller")
                }
            }
        }

        /// Under its numbers the name has the row's width less the caret's. Measured: "Hyperextension" stands
        /// on one line up to `.accessibility3` on both widths and is broken in two at `.accessibility4` on
        /// 375 pt and at `.accessibility5` on both (a note in the findings: at those sizes no line holds it).
        @Test(
            "A one-word name is whole on its line up to accessibility3, where the numbers stand under it",
            arguments: [DynamicTypeSize.accessibility1, .accessibility3], ViewsSetting.widths
        )
        func oneWordName_overItsNumbers_isNotBroken(_ size: DynamicTypeSize, _ width: CGFloat) throws {
            for isBold in [false, true] {
                let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                let growth = try Self.growth(of: "Hyperextension", load: "180 lb", setting)
                #expect(growth < 1, "\(setting.testDescription): the row is \(growth) pt taller")
            }
        }
    }

    // MARK: - The steppers' round buttons, the caret, the strip's shown week

    extension DayEditorViewsLayoutAdversarialTests {
        /// The box, in points, around everything `view` draws that is not the dark ground.
        static func inkBox(of view: some View, _ size: DynamicTypeSize, width: CGFloat = 335) throws -> CGRect {
            let scale: CGFloat = 3
            let drawn = try ProgramDrawing.pixels(
                of: view.environment(\.dynamicTypeSize, size), .dark, width: width, scale: scale
            )
            var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
            for (place, pixel) in drawn.pixels.enumerated() where pixel.red > 24 {
                let (across, down) = (place % drawn.width, place / drawn.width)
                (minX, maxX) = (min(minX, across), max(maxX, across))
                (minY, maxY) = (min(minY, down), max(maxY, down))
            }
            guard maxX >= 0 else {
                return .zero
            }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                .applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        }

        /// The steppers are one adjustable element each, so "−" and "+" are no stops and no frame of the
        /// tree measures them. Under an empty label and value a stepper draws its two rings and nothing
        /// else: the box around them is two targets and the gap between them.
        @Test(
            "A stepper's two round buttons are 44 pt each, at the smallest and the largest text size",
            arguments: [DynamicTypeSize.xSmall, .large, .accessibility5]
        )
        func stepper_roundButtons_are44Points(_ size: DynamicTypeSize) throws {
            let field = try #require(ProgramPreview.dayOpenLinear.dayEditorModel().openRow?.panel?.details?.fields
                .first)
            let bare = SlotEditorModel.Field(
                kind: field.kind, label: "", value: "", spokenLabel: "", decrement: field.decrement,
                increment: field.increment
            )
            let box = try Self.inkBox(of: SlotStepper(field: bare) { _ in }, size)
            #expect(box.height >= 43.5, "\(box.height) pt high")
            #expect(box.width >= 2 * 43.5 + LedgerSpacing.s, "\(box.width) pt for the two and their gap")
        }

        /// How wide the top fifth and the bottom fifth of what `view` draws in its last `side` points are.
        static func caretSpread(
            of view: some View,
            side: CGFloat,
            isRightToLeft: Bool
        ) throws -> (top: Int, bottom: Int) {
            let width: CGFloat = 335
            let drawn = try ProgramDrawing.pixels(
                of: view.environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight), .dark,
                width: width, scale: 3
            )
            let columns = isRightToLeft ? 0 ..< Int(side * 3) : drawn.width - Int(side * 3) ..< drawn.width
            // Brighter than a rule: the caret's grey.
            let lit = (0 ..< drawn.height).map { down in
                columns.filter { drawn.pixels[down * drawn.width + $0].red > 70 }
            }
            let rows = lit.indices.filter { !lit[$0].isEmpty }
            guard let first = rows.first, let last = rows.last, last - first >= 6 else {
                return (0, 0)
            }
            let fifth = (last - first + 1) / 5
            func spread(_ range: ClosedRange<Int>) -> Int {
                let all = range.flatMap { lit[$0] }
                return (all.max() ?? 0) - (all.min() ?? 0)
            }
            return (spread(first ... first + fifth), spread(last - fifth ... last))
        }

        /// Criterion 5, "a caret by `isOpen`", by the pixels: a caret that points down is wide at its top and
        /// a point at its bottom. No tree reads the caret, and right to left a mirrored chevron turned the
        /// same quarter would point the other way.
        @Test("A closed row's caret points down and the open row's up, right to left too", arguments: [false, true])
        func caret_pointsDownWhenClosed_upWhenOpen(_ isRightToLeft: Bool) throws {
            let model = try ProgramPreview.dayOpenLinear.dayEditorModel()
            let open = try #require(model.openRow?.withoutItsPanel)
            let closed = try #require(model.rows.last)
            let side = LedgerFont.scaledSize(.body, dynamicTypeSize: .large)
            let down = try Self.caretSpread(
                of: ExerciseRow(row: closed) { _ in },
                side: side,
                isRightToLeft: isRightToLeft
            )
            let upward = try Self.caretSpread(
                of: ExerciseRow(row: open) { _ in },
                side: side,
                isRightToLeft: isRightToLeft
            )
            #expect(down.top > down.bottom * 2 && down.top > 10, "closed: \(down)")
            #expect(upward.bottom > upward.top * 2 && upward.bottom > 10, "open: \(upward)")
        }

        /// The brightest red a view draws in the dark theme.
        static func brightest(_ view: some View) throws -> Int {
            try Int(ProgramDrawing.pixels(of: view, .dark).pixels.map(\.red).max() ?? 0)
        }

        /// `Entry.isShown` picks ink against grey (the notes' list of facts), which no tree reads.
        @Test("In the week strip the shown week is ink and every other week grey")
        func strip_shownWeekIsInk() throws {
            func strip(isShown: Bool) -> WeekLoads {
                let entry = SlotEditorModel.Entry(text: "W3 190", isDeload: false, isHeld: false, isShown: isShown)
                return WeekLoads(strip: SlotEditorModel.WeekStrip(text: "W3 190", entries: [entry]))
            }
            let (shown, other) = try (Self.brightest(strip(isShown: true)), Self.brightest(strip(isShown: false)))
            #expect(shown > 200 && other < 190 && other > 90, "shown \(shown), another week \(other)")
        }

        /// Ruling 17 (decision 1 A's words over criterion 7): a stepper is drawn with `spokenLabel` ("Rep
        /// floor") and `value`. Its `label` ("REP FLOOR") is another string of the model, and the tree
        /// cannot tell which of the two is drawn.
        @Test("A stepper draws the field's spoken label, not its capital label")
        func stepper_drawsTheSpokenLabel() throws {
            let field = try #require(ProgramPreview.dayOpenDouble.dayEditorModel().openRow?.panel?.details?.fields[1])
            #expect(field.label == "REP FLOOR" && field.spokenLabel == "Rep floor")
            func drawn(_ view: some View) throws -> PixelBuffer {
                try ProgramDrawing.pixels(of: view, .dark)
            }
            let stepper = try drawn(SlotStepper(field: field) { _ in })
            let isTheLabel = try stepper == drawn(StepperField(
                field.label,
                value: field.value,
                onDecrement: {},
                onIncrement: {}
            ))
            let isTheSpoken = try stepper == drawn(
                StepperField(field.spokenLabel, value: field.value, onDecrement: {}, onIncrement: {})
            )
            #expect(!isTheLabel && isTheSpoken)
        }
    }
#endif
