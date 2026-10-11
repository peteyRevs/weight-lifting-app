#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, gate G2, round 2, rulings 15 and 16: `NameField`, the day's name drawn twice, as a text that
    /// wraps and as the one-line field over its first line, one of the two shown at a time.
    ///
    /// **What the lifter sees** is measured against a text of this tester's own: the name set in the title's
    /// type with no limit of lines, which cannot lose a word. While the field has no focus the name field
    /// must draw exactly that, pixel for pixel, at every text size.
    ///
    /// **Which of the two is drawn** is found by hiding the `UITextField` and drawing again: what is still
    /// there is the text's, what went was the field's.
    ///
    /// **Not reached by a hosted test:** a finger. That a tap on the name's second line gives the field the
    /// focus is SwiftUI's gesture, which no hosted test can send; here the target's frame is measured
    /// against the drawn name, and UIKit is asked what stands under a point of each line.
    @Suite("Adversarial F11 S10 · the name field, drawn and hidden", .serialized, .tags(.feature))
    struct DayEditorViewsNameAdversarialTests {
        typealias Hosted = ProgramTextFieldTests.Hosted
        typealias Field = DayEditorViewsFieldAdversarialTests

        static func field(_ name: String, label: String = "Day name") -> NameField {
            NameField(label: label, name: name) { _ in }
        }

        /// The name as this tester sets it: whole, in the title's type, on as many lines as it needs, at the
        /// top of a 44 pt target. Written from ruling 15 and the type scale, not from `NameField`.
        static func whole(_ name: String) -> some View {
            Text(verbatim: name)
                .ledgerFont(.title)
                .foregroundStyle(LedgerColor.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }

        static func drawn(
            _ view: some View,
            _ setting: ViewsSetting,
            _ theme: ColorScheme = .dark
        ) throws -> PixelBuffer {
            let set = view
                .environment(\.dynamicTypeSize, setting.size)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
            return try ProgramDrawing.pixels(of: set, theme, width: setting.width - 2 * LedgerSpacing.screen)
        }

        /// The names of `names` that the field, without the focus, does not draw exactly as `whole` does.
        static func notWhole(_ names: [String], at size: DynamicTypeSize) throws -> [String] {
            var lines: [String] = []
            for width in ViewsSetting.widths {
                for isBold in [false, true] {
                    let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                    for name in names {
                        let (field, whole) = try (drawn(Self.field(name), setting), drawn(Self.whole(name), setting))
                        if field != whole {
                            let heights = "\(field.height), not \(whole.height)"
                            lines.append("\(setting.testDescription): \(name.prefix(24)) \(heights)")
                        }
                    }
                }
            }
            return lines
        }

        /// Round 1's finding F11-S10-1, closed by ruling 15: where the one-line field read "Lower A — Squat
        /// foc…" from `.xLarge`, the name now wraps. No known issue is left here.
        @Test(
            "Without the focus each seed day's name is drawn whole, on both widths, plain and bold",
            arguments: DynamicTypeSize.allCases
        )
        func seedNames_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let lines = try Self.notWhole(Field.seedNames, at: size)
            #expect(lines.isEmpty, "\(lines.count) differ: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "A long name, a name of one long word and a name of one letter are drawn whole too",
            arguments: [DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility5]
        )
        func otherNames_areDrawnWhole(_ size: DynamicTypeSize) throws {
            let lines = try Self.notWhole([DayViewsState.longDay, "Hyperextensions", "A"], at: size)
            #expect(lines.isEmpty, "\(lines.count) differ: \(lines.prefix(3).joined(separator: "; "))")
        }

        @Test("The measure sees a name cut to one line, and a name that is drawn twice a point apart")
        func measure_seesACutAndADouble() throws {
            let setting = ViewsSetting(size: .xLarge, width: 375)
            let name = Field.seedNames[1]
            let whole = try Self.drawn(Self.whole(name), setting)
            let isCutSeen = try Self.drawn(Self.whole(name).lineLimit(1), setting) != whole
            let twice = Self.whole(name).overlay(alignment: .topLeading) { Self.whole(name).offset(y: 1) }
            let isDoubleSeen = try Self.drawn(twice, setting) != whole
            #expect(isCutSeen && isDoubleSeen)
            #expect(whole.height > 60, "the name is on two lines at this size: \(whole.height) pt")
        }

        /// Right to left the name starts at the right edge, and the two themes draw the same letters.
        @Test("Right to left and in the light theme the name is the same whole name", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func rightToLeft_andLight_areDrawnWhole(_ size: DynamicTypeSize) throws {
            for name in [Field.seedNames[1], DayViewsState.longDay] {
                let mirrored = ViewsSetting(size: size, width: 375, isRightToLeft: true)
                let isSameMirrored = try Self.drawn(Self.field(name), mirrored) == Self.drawn(
                    Self.whole(name),
                    mirrored
                )
                let plain = ViewsSetting(size: size, width: 375)
                let isSameLight = try Self.drawn(Self.field(name), plain, .light) == Self.drawn(
                    Self.whole(name),
                    plain,
                    .light
                )
                #expect(
                    isSameMirrored && isSameLight,
                    "\(name.prefix(24)): mirrored \(isSameMirrored), light \(isSameLight)"
                )
            }
        }
    }

    // MARK: - Which of the two is drawn

    extension DayEditorViewsNameAdversarialTests {
        /// A hosted name field, 323 pt wide on the dark ground, drawn as it stands.
        final class Shown {
            let hosted: Hosted
            let field: UITextField
            /// The drawing's scale: 3 where a box is measured, 1 where two drawings are only compared.
            var scale: CGFloat = 3

            /// `isMarked`: the field's target is blue behind it; without, it stands on the ground.
            init(
                _ name: String, at size: DynamicTypeSize = .large, isRightToLeft: Bool = false, isMarked: Bool = true
            ) throws {
                hosted = Hosted(Shown.view(name, size, isRightToLeft, isMarked: isMarked))
                hosted.host.overrideUserInterfaceStyle = .dark
                hosted.settle()
                field = try #require(hosted.fields.first)
            }

            static func view(
                _ name: String, _ size: DynamicTypeSize, _ isRightToLeft: Bool, isMarked: Bool = true
            ) -> some View {
                VStack(spacing: 0) {
                    DayEditorViewsNameAdversarialTests.field(name)
                        .frame(width: 323)
                        .background(
                            isMarked ? Color(red: 0, green: 0, blue: 1) : LedgerColor.ground,
                            ignoresSafeAreaEdges: []
                        )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .background(LedgerColor.ground)
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            }

            func focus(_ isFocused: Bool) throws {
                try #require(isFocused ? field.becomeFirstResponder() : field.resignFirstResponder())
                hosted.settle()
                hosted.settle()
            }

            /// The window's pixels at 3×, with the `UITextField` hidden or not.
            func pixels(hidingTheField: Bool = false) throws -> PixelBuffer {
                field.isHidden = hidingTheField
                defer { field.isHidden = false }
                let view: UIView = hosted.host.view
                view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                // The top of the window is enough: the name stands under the window's top inset.
                let top = CGRect(x: 0, y: 0, width: view.bounds.width, height: 520)
                let image = UIGraphicsImageRenderer(bounds: top, format: format).image {
                    view.layer.render(in: $0.cgContext)
                }
                return try #require(image.cgImage.flatMap(PixelBuffer.init))
            }

            /// The box, in points, around the pixels `isIncluded` picks; `.null` when there is none.
            func box(hidingTheField: Bool = false, _ isIncluded: (Pixel) -> Bool) throws -> CGRect {
                let drawn = try pixels(hidingTheField: hidingTheField)
                var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
                for (place, pixel) in drawn.pixels.enumerated() where isIncluded(pixel) {
                    let (across, down) = (place % drawn.width, place / drawn.width)
                    (minX, maxX) = (min(minX, across), max(maxX, across))
                    (minY, maxY) = (min(minY, down), max(maxY, down))
                }
                guard maxX >= 0 else {
                    return .null
                }
                return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                    .applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            }

            /// Where letters are drawn: the ink, near white, and never the caret's or the marker's blue.
            func letters(hidingTheField: Bool = false) throws -> CGRect {
                try box(hidingTheField: hidingTheField) { $0.red > 150 && $0.green > 150 }
            }

            /// Anything that is neither the ground, the marker under the field nor the caret, which is blue:
            /// letters, a placeholder.
            func anything(hidingTheField: Bool = false) throws -> CGRect {
                try box(hidingTheField: hidingTheField) { $0.red > 40 && Int($0.blue) - Int($0.red) < 60 }
            }

            /// The name field's own frame: the blue marker behind it, with what is drawn on it.
            func target() throws -> CGRect {
                try box { $0.blue > 60 }
            }

            func close() {
                hosted.close()
            }
        }

        /// One of the two is drawn, never both and never neither, while there is a name to draw.
        @Test(
            "Without the focus the text draws the name and the field nothing; with it, the other way round",
            arguments: ["Upper A", DayViewsState.longDay], [false, true]
        )
        func oneOfTheTwo_isDrawn(_ name: String, _ isRightToLeft: Bool) throws {
            let shown = try Shown(name, isRightToLeft: isRightToLeft)
            defer { shown.close() }
            shown.scale = 1
            for round in 1 ... 2 {
                let isTheTextAlone = try shown.pixels() == shown.pixels(hidingTheField: true)
                #expect(isTheTextAlone, "round \(round): without the focus the field draws something")
                #expect(try !shown.letters().isNull, "round \(round): no name is drawn without the focus")
                try shown.focus(true)
                #expect(
                    try shown.letters(hidingTheField: true).isNull,
                    "round \(round): the text is drawn under the field"
                )
                #expect(try !shown.letters().isNull, "round \(round): the field with the focus draws no name")
                try shown.focus(false)
            }
        }

        @Test("An empty name shows the placeholder once, from the field, with the focus and without", arguments: [
            "", "   "
        ])
        func emptyName_showsThePlaceholderOnce(_ name: String) throws {
            let shown = try Shown(name, isMarked: false)
            defer { shown.close() }
            shown.scale = 1
            for isFocused in [false, true] {
                if isFocused {
                    try shown.focus(true)
                }
                #expect(
                    try shown.anything(hidingTheField: true).isNull,
                    "focus \(isFocused): the text draws under the field"
                )
                // A name of spaces is no empty name to UIKit: the field keeps its placeholder back, and the
                // lifter sees nothing at all (the stored name is cleaned, so only a draft can be spaces).
                let isBlank = try shown.anything().isNull
                #expect(isBlank == !name.isEmpty, "focus \(isFocused): nothing is drawn: \(isBlank)")
                #expect(try shown.letters(hidingTheField: true).isNull)
            }
            #expect(shown.field.placeholder == "Day name")
        }
    }
#endif
