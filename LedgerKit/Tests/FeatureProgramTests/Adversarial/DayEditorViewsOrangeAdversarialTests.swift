#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, gate G2, round 1, criterion 8 (Pete's decision 1, A) from the other side.
    /// `DayEditorOrangeAuditTests` shows that named parts are orange or are not. Here the one thing that may
    /// be orange, the open exercise's week eyebrow in a deload week or a held one, is taken out of the model
    /// and the whole page must then hold no orange pixel, in fifteen states and both themes; with it left
    /// in, the page is orange exactly when the model says so; and the orange is the eyebrow's words and
    /// nothing beside them.
    @Suite("Adversarial F11 S10 · the orange audit, whole pages", .serialized, .tags(.feature))
    struct DayEditorViewsOrangeAdversarialTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        static func orange(in model: DayEditorModel.Content, _ theme: ColorScheme) throws -> Int {
            try ProgramDrawing.orangePixels(in: DayEditorParts(model: model), theme)
        }

        /// Whether the notes' list lets `model`'s page be orange: an exercise is open, it is stored, and its
        /// week line says deload or held.
        nonisolated static func mayBeOrange(_ model: DayEditorModel.Content) -> Bool {
            model.rows.contains { $0.panel?.details.map { $0.week.isDeload || $0.week.isHeld } ?? false }
        }

        @Test("Without a deload or held week line, no state of the Day editor draws an orange pixel", arguments: themes)
        func withoutItsOrange_drawsNone(_ theme: ColorScheme) throws {
            for (name, model) in try DayViewsProbe.models() {
                #expect(try Self.orange(in: DayViewsText.withoutItsOrange(model), theme) == 0, "\(name)")
            }
        }

        @Test(
            "A page is orange exactly when its open exercise's week is a deload week or a held one",
            arguments: themes
        )
        func isOrangeWhenTheModelSaysSo(_ theme: ColorScheme) throws {
            var orangeStates = 0
            for (name, model) in try DayViewsProbe.models() {
                let count = try Self.orange(in: model, theme)
                #expect((count > 0) == Self.mayBeOrange(model), "\(name): \(count) orange pixels")
                orangeStates += Self.mayBeOrange(model) ? 1 : 0
            }
            #expect(orangeStates == 3, "the preview's deload week, this tester's, and the held week")
        }

        /// The listed place really is the orange one: with the eyebrow's words gone the orange is gone,
        /// and it comes back with any words at all, whatever they say.
        @Test("The orange of a deload or held week is its eyebrow's words and nothing beside them", arguments: themes)
        func theOrange_isTheEyebrow(_ theme: ColorScheme) throws {
            for state in [DayViewsState.deloadSupersetOpen, .heldWeek] {
                let model = try state.model()
                let without = DayViewsText.changing("panel.week.eyebrow", to: "", in: model)
                #expect(try Self.orange(in: without, theme) == 0, "\(state)")
                let other = DayViewsText.changing("panel.week.eyebrow", to: "WEEK 2", in: model)
                #expect(try Self.orange(in: other, theme) > 0, "\(state): the fact picks the colour, not the word")
            }
        }

        @Test("At the largest text size and with Bold Text the same holds", arguments: themes)
        func largestText_bold_sameOrange(_ theme: ColorScheme) throws {
            for state in [DayViewsState.deloadSupersetOpen, .heldWeek, .twelve] {
                let model = try state.model()
                func count(_ model: DayEditorModel.Content) throws -> Int {
                    let parts = DayEditorParts(model: model)
                        .environment(\.dynamicTypeSize, .accessibility5)
                        .environment(\.legibilityWeight, .bold)
                    return try ProgramDrawing.orangePixels(in: parts, theme)
                }
                #expect(try (count(model) > 0) == Self.mayBeOrange(model), "\(state)")
                #expect(try count(DayViewsText.withoutItsOrange(model)) == 0, "\(state)")
            }
        }

        @Test("The check sees an orange word on a Day editor's page", arguments: themes)
        func check_seesOrange(_ theme: ColorScheme) throws {
            let model = try DayViewsText.withoutItsOrange(DayViewsState.deloadSupersetOpen.model())
            let page = VStack {
                DayEditorParts(model: model)
                Eyebrow("DELOAD", tint: .accent)
            }
            #expect(try ProgramDrawing.orangePixels(in: page, theme) > 0)
        }
    }

    // MARK: - The day's name

    /// F11 S10, gate G2, round 1, criterion 4: the name field's draft rule, as far as a hosted test reaches
    /// it. **Typing does not reach SwiftUI from a hosted `UITextField`** (S9's tester tried three ways), so
    /// what the field sends for a typed name, a blank one among them, stays with the UI tests of S14. What
    /// is held here is what the field must show and must not send.
    @Suite("Adversarial F11 S10 · the day's name", .serialized, .tags(.feature))
    struct DayEditorViewsFieldAdversarialTests {
        typealias Hosted = ProgramTextFieldTests.Hosted

        static func header(_ name: String, sent: @escaping (DayEditorAction) -> Void) throws -> DayEditorHeader {
            let model = try ProgramPreview.dayEditor.dayEditorModel()
            return DayEditorHeader(model: DayViewsText.changing("header.name", to: name, in: model), send: sent)
        }

        @Test(
            "The name field sends nothing for a focus, a blur, or a stored name that changes under either",
            arguments: ["Upper A", "", "  two  spaces  ", DayViewsState.longDay]
        )
        func nameField_focusAndBlur_sendNothing(_ name: String) throws {
            var sent: [DayEditorAction] = []
            let hosted = try Hosted(Self.header(name) { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            #expect(field.text == name, "the field shows the stored name as it is stored")
            try #require(field.becomeFirstResponder())
            hosted.settle()
            try hosted.show(Self.header(name + " B") { sent.append($0) })
            #expect(field.text == name, "a field being edited keeps its draft")
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(field.text == name + " B")
            try hosted.show(Self.header("") { sent.append($0) })
            #expect(field.text?.isEmpty == true, "a stored name that is empty empties the field")
            try hosted.show(Self.header(name) { sent.append($0) })
            #expect(field.text == name, "and the next stored name fills it again")
            #expect(sent.isEmpty, "\(sent.count) actions")
        }

        /// Two changes of the stored name while the field has focus, then a blur: the field takes the last
        /// one, not the first, and not its old draft.
        @Test("After a blur the field holds the latest stored name, however often it changed under the focus")
        func nameField_blur_takesTheLatestStoredName() throws {
            var sent: [DayEditorAction] = []
            let hosted = try Hosted(Self.header("Upper A") { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            try #require(field.becomeFirstResponder())
            hosted.settle()
            for name in ["Upper", "Upper B", "Push"] {
                try hosted.show(Self.header(name) { sent.append($0) })
                #expect(field.text == "Upper A")
            }
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(field.text == "Push" && sent.isEmpty, "\(field.text ?? "") after \(sent.count) actions")
        }

        /// The field is no stop of the hosted tree, so no 44 pt check measures it. It stands between the
        /// heading and the summary line, `xs` from each: the room between those two is the field's target.
        @Test("The name field's row is a 44 pt target, at the smallest sizes too", arguments: [
            DynamicTypeSize.xSmall, .large
        ])
        func nameField_is44PointsHigh(_ size: DynamicTypeSize) throws {
            let stops = try Self.header("Arms") { _ in }.placedStops(SnapshotAppearance(.light, size))
            let heading = try #require(stops.first { $0.stop.kind == .heading }).frame
            let line = try #require(stops.last).frame
            let room = line.minY - heading.maxY
            #expect(room >= 44 + 2 * LedgerSpacing.xs - 1, "\(room) pt between the heading and the line")
        }

        /// How wide the field draws `text`, and the room it has for it. The width is the field's own
        /// attributed text's, which carries the title's tracking: the font alone measures 4 % too wide
        /// (checked against four pictures: at `.large` on 375 pt "Lower A — Squat focus" is drawn whole, 310.5
        /// of 323 pt, and at `.xLarge` it reads "Lower A — Squat foc…", 325.8 of 323).
        static func room(for text: String, _ setting: ViewsSetting) throws -> (needs: CGFloat, has: CGFloat) {
            let header = try Self.header(text) { _ in }
                .frame(width: setting.width)
                .environment(\.dynamicTypeSize, setting.size)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
            let hosted = Hosted(header)
            defer { hosted.close() }
            hosted.settle()
            let field = try #require(hosted.fields.first)
            let needs = try #require(field.attributedText).size().width
            return (needs, field.textRect(forBounds: field.bounds).width)
        }

        nonisolated static let seedNames = [
            "Upper A — Push focus", "Lower A — Squat focus", "Upper B — Pull focus", "Lower B — Hinge focus"
        ]

        /// The seed names wider than the field at `size`, on both widths, plain and with Bold Text; a line each.
        static func seedNamesCut(at size: DynamicTypeSize) throws -> [String] {
            var lines: [String] = []
            for name in seedNames {
                for width in ViewsSetting.widths {
                    for isBold in [false, true] {
                        let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                        let room = try Self.room(for: name, setting)
                        if room.needs > room.has + 0.5 {
                            lines
                                .append(
                                    "\(setting.testDescription): \(name) needs \(Int(room.needs)) of \(Int(room.has))"
                                )
                        }
                    }
                }
            }
            return lines
        }

        /// A guard for the finding below: up to the default text size the four seed names fit their line.
        @Test(
            "Up to the default text size no seed day's name is cut in its field, on either width",
            arguments: [DynamicTypeSize.xSmall, .large]
        )
        func seedNames_upToTheDefaultSize_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let cut = try Self.seedNamesCut(at: size)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(4).joined(separator: "; "))")
        }

        /// **FINDING F11-S10-1** (should fix, or the product owner's to accept: open question 2 of the S10
        /// notes, with the facts corrected). Criterion 11 asks that no word is cut at the twelve sizes on 375
        /// and 402 pt. The implementer's finding 1 says the seed's name "fits at the default size and ends in
        /// '…' at `.accessibility3`". Measured from the field's own attributed text and its text rectangle,
        /// the cut starts one step above the default size. On a 375 pt phone "Lower A — Squat focus" and
        /// "Lower B — Hinge focus" read "Lower A — Squat foc…" from `.xLarge` (325 pt of text in 323),
        /// "Upper A — Push focus" from `.xxLarge` and "Upper B — Pull focus" from `.xxxLarge`; on an iPhone 17
        /// the two Lower days are cut at `.xxLarge` with Bold Text, and they and Upper A from `.xxxLarge`. A
        /// known issue until the product owner decides; it fails, and is then to be removed, when the names
        /// are drawn whole.
        @Test(
            "Above the default text size no seed day's name is cut in its field",
            arguments: [DynamicTypeSize.xLarge, .xxLarge, .xxxLarge, .accessibility3]
        )
        func seedNames_aboveTheDefaultSize_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let cut = try Self.seedNamesCut(at: size)
            withKnownIssue("Open question 2 of the S10 notes: the day's name in a one-line field") {
                #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(4).joined(separator: "; "))")
            }
        }
    }
#endif
