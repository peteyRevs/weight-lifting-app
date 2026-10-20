#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// The chore of 2026-10-13 (`tasks/chores/2026-10-13-name-field-line-height.md`), gate G2: the name
    /// field on a line of `LedgerFont.fieldLineHeight`, in the Day editor and, new, in the builder's header.
    /// Everything is measured from a hosted window at 3×, 323 pt wide (a 375 pt phone's page), as the tester
    /// of F11 S10 measured the day's name. Findings are `NF-1`… in the record, "G2 — adversarial testing".
    ///
    /// **Not reached by a hosted test:** typing and a finger (`ProgramTextFieldTests`), and a device set to
    /// a right-to-left language.
    @Suite("Adversarial chore 2026-10-13 · the name field's line", .serialized, .tags(.feature))
    struct NameFieldLineAdversarialTests {
        typealias Shown = DayEditorViewsNameAdversarialTests.Shown

        /// The sizes most of these checks measure: the default, `.accessibility3` and the largest. On the
        /// hosted PR runner (`TestSweep`) the default and the largest; a check pinned to `.accessibility3`, where
        /// a measure stands nearest its bound, names it.
        nonisolated static let sizes = TestSweep.sizes([.large, .accessibility3, .accessibility5])

        /// The two places a name is edited. The builder's header is drawn without its eyebrow where only the
        /// name's ink is measured.
        nonisolated enum Place: String, CaseIterable, Sendable, CustomTestStringConvertible {
            case day, program

            var testDescription: String {
                rawValue
            }

            @MainActor
            func view(_ name: String) -> AnyView {
                switch self {
                case .day:
                    AnyView(NameField(label: "Day name", name: name) { _ in })
                case .program:
                    AnyView(ProgramHeader(
                        model: ProgramBuilderModel.Header(eyebrow: "", name: name, namePlaceholder: "Program name")
                    ) { _ in })
                }
            }
        }

        /// What is drawn of a name, without the focus and with it: anything but the ground and the caret.
        static func drawn(_ view: some View, at size: DynamicTypeSize) throws -> (idle: CGRect, focused: CGRect) {
            let shown = try Shown(hosting: view, at: size)
            defer { shown.close() }
            let idle = try shown.anything()
            try shown.focus(true)
            return try (idle, shown.anything())
        }

        /// Not measured by the implementer: accents over capitals, marks under the line deeper than a tail,
        /// scripts Archivo does not hold (the system's fonts stand in) and emoji. Measured: nothing is cut in
        /// either field, plain or bold; the least is a third of a point (one pixel) on "Ǻ Ṩ ự" with Bold
        /// Text. Thai is drawn 4.0 to 6.7 pt higher by the field than by the text (its marks spread).
        /// On `main` the Thai name lost 0.7 to 2.0 pt in the Day editor and 6.7 to 12.0 pt in the builder.
        @Test(
            "With the focus accents, deep marks, other scripts and emoji are drawn whole, plain and bold",
            arguments: sizes
        )
        func focus_keepsAccentsMarksAndEmojiWhole(_ size: DynamicTypeSize) throws {
            var cut: [String] = []
            for place in Place.allCases {
                for weight in [LegibilityWeight.regular, .bold] {
                    for name in ["ÅÉÇ", "ąỵgj", "Ǻ Ṩ ự", "ก้ำปู่ ฏู", "कृष्ण हिंदी", "🏋️💪 Gy"] {
                        let view = place.view(name).environment(\.legibilityWeight, weight)
                        let (idle, focused) = try Self.drawn(view, at: size)
                        if focused.height < idle.height - 0.5 || idle.isNull {
                            cut.append("\(place) \(weight) \(name): \(idle.height) pt, \(focused.height) focused")
                        }
                    }
                }
            }
            #expect(cut.isEmpty, "\(cut.count) are cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        /// The names the field's guide is right for: the letters stand where the text's do, to the bound the
        /// tester of S10 set (a point and a third), also where a letter has an accent or the name a dash.
        /// `.accessibility3` on every runner: there the field stands 1 pt higher, nearest the bound.
        @Test(
            "When the focus comes a name stays where it is, in both fields, plain and bold",
            arguments: Place.allCases, [DynamicTypeSize.large, .accessibility3]
        )
        func focus_doesNotMoveTheName(_ place: Place, _ size: DynamicTypeSize) throws {
            for weight in [LegibilityWeight.regular, .bold] {
                for name in ["Upper A", "Día — é", "Pete’s ½ × 3"] {
                    let view = place.view(name).environment(\.legibilityWeight, weight)
                    let (idle, focused) = try Self.drawn(view, at: size)
                    let (across, down) = (focused.minX - idle.minX, focused.minY - idle.minY)
                    #expect(abs(across) < 0.34 && abs(down) < 1.34, "\(weight) \(name): \(across) pt, \(down) pt")
                }
            }
        }

        /// Round 2 of G2: Vietnamese stacks a tone mark over a vowel mark ("ấ", "Ậ"), the case option A of
        /// NF-1 would have cut. Measured: whole under the focus in both fields, plain and bold, at the three
        /// sizes (the name of three words wraps at `.accessibility5` without the focus and is not measured
        /// there); and every one of these names is lifted as NF-1 says, 3.7, 6.0 and 7.3 pt.
        @Test(
            "With the focus Vietnamese stacked marks are drawn whole, small and capital, plain and bold",
            arguments: sizes
        )
        func focus_keepsVietnameseWhole(_ size: DynamicTypeSize) throws {
            var cut: [String] = []
            for place in Place.allCases {
                for weight in [LegibilityWeight.regular, .bold] {
                    for name in ["ấ ầ ẩ ẫ ậ ế ồ", "Ấ Ầ Ẩ Ẫ Ậ Ế Ồ", "Ặ Ẵ Ỗ Ữ ỹ", "Tiếng Việt"] {
                        let view = place.view(name).environment(\.legibilityWeight, weight)
                        let (idle, focused) = try Self.drawn(view, at: size)
                        if focused.height < idle.height - 0.5 || idle.isNull {
                            cut.append("\(place) \(weight) \(name): \(idle.height) pt, \(focused.height) focused")
                        }
                    }
                }
            }
            #expect(cut.isEmpty, "\(cut.count) are cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        nonisolated static let liftedName: Comment = """
        NF-1: a name with an emoji, or with one of Å É Ç Ł ï ą ỵ, or in Thai, Devanagari or Arabic, is lifted \
        3.7 pt at .large and 6.0 pt at .accessibility3 when the focus comes (7.3 at .accessibility5), where \
        main lifts every name 0.7 and 1.3 pt. For such a line UIKit does not centre the letters in the \
        field's higher line, and the field's .top guide lifts it all the same.
        """

        /// **FINDING NF-1** (new with this chore). The guide of `ledgerFieldFont` is right only for a line
        /// UIKit centres. It fails when the lift is gone: remove the wrapper then.
        @Test(
            "When the focus comes a name with an emoji or one of Å Ł ï stays where it is (known: NF-1)",
            arguments: Place.allCases, TestSweep.sizes([.large, .accessibility3])
        )
        func focus_doesNotMoveANameWithAnEmoji(_ place: Place, _ size: DynamicTypeSize) throws {
            for name in ["Push 💪", "naïve", "Łódź", "ÅÉÇ", "Tiếng Việt"] {
                let (idle, focused) = try Self.drawn(place.view(name), at: size)
                let down = focused.minY - idle.minY
                withKnownIssue(Self.liftedName) {
                    #expect(abs(down) < 1.34, "\(name): the name moves \(down) pt down")
                }
            }
        }

        /// The builder's header as this tester sets it: no eyebrow, and under it the tester's own text of S10
        /// (`whole`, which cannot lose a word) with the room the header keeps under the name.
        static func wholeHeader(_ name: String) -> some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                Eyebrow("")
                DayEditorViewsNameAdversarialTests.whole(name).padding(.bottom, LedgerSpacing.s)
            }
        }

        /// The builder's name was one line that ended in "…". Now it is the whole name, pixel for pixel, on
        /// both phones: a long name, a name of one long word, a name of one letter.
        @Test(
            "Without the focus a long program name is drawn whole, on both widths, plain and bold",
            arguments: sizes
        )
        func longProgramName_isDrawnWhole(_ size: DynamicTypeSize) throws {
            typealias Name = DayEditorViewsNameAdversarialTests
            for name in [ProgramPreviewData.longName, "Supercalifragilisticexpialidocious", "g"] {
                for width in ViewsSetting.widths {
                    for isBold in [false, true] {
                        let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                        let header = try Name.drawn(Place.program.view(name), setting)
                        let whole = try Name.drawn(Self.wholeHeader(name), setting)
                        let isWhole = header == whole
                        let heights = "\(header.height) pt, not \(whole.height)"
                        #expect(isWhole, "\(setting.testDescription): \(name.prefix(16)): \(heights)")
                    }
                }
            }
        }

        @Test(
            "With the focus a long program name or word is one line, and the same picture after the blur",
            arguments: ["Supercalifragilisticexpialidocious", ProgramPreviewData.longName],
            [DynamicTypeSize.large, .accessibility5]
        )
        func longProgramName_isOneLineWhileEdited(_ name: String, _ size: DynamicTypeSize) throws {
            let line = LedgerFont.scaledSize(.title, dynamicTypeSize: size)
            let shown = try Shown(hosting: Place.program.view(name), at: size)
            defer { shown.close() }
            let before = try shown.pixels()
            let idle = try shown.letters()
            try shown.focus(true)
            let with = try shown.letters()
            #expect(idle.height > 1.7 * line && with.height < 1.1 * line, "\(idle.height) pt, then \(with.height)")
            #expect(abs(with.minY - idle.minY) < 2 && with.width > 300, "\(idle), then \(with)")
            try shown.focus(false)
            let isAsBefore = try shown.pixels() == before
            #expect(isAsBefore, "after the blur the picture is another")
        }
    }
#endif
