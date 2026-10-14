#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // F11 S10, gate G2, round 2: the name field at the moment the focus comes and goes, its target, and the
    // stored name changing under it.

    extension DayEditorViewsNameAdversarialTests {
        /// The implementer reports that the name's first line moves by 0 pt sideways and 0.7 to 1.0 pt up
        /// when the field takes the focus. Measured here from the letters' box at 3×, on a name of one line.
        @Test("When the focus comes a one-line name stays where it is, to a point and a third", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func focus_doesNotMoveTheName(_ size: DynamicTypeSize) throws {
            let shown = try Shown("Upper A", at: size)
            defer { shown.close() }
            let before = try shown.letters()
            try shown.focus(true)
            let with = try shown.letters()
            try shown.focus(false)
            let after = try shown.letters()
            let (across, down) = (with.minX - before.minX, with.minY - before.minY)
            #expect(abs(across) < 0.34, "\(size): the name moves \(across) pt sideways")
            #expect(abs(down) < 1.34, "\(size): the name moves \(down) pt down")
            #expect(after == before, "after the focus \(after), before it \(before)")
        }

        /// How high the letters of "Gyp" are in the one text field of `view`, without the focus and with it.
        static func lettersOfGyp(
            in view: some View,
            at size: DynamicTypeSize
        ) throws -> (whole: CGFloat, focused: CGFloat) {
            let shown = try Shown(hosting: view, at: size)
            defer { shown.close() }
            let before = try shown.letters()
            try shown.focus(true)
            return try (before.height, shown.letters().height)
        }

        /// **FINDING F11-S10-5**, ruled out of that slice (ruling 22), a known issue until the chore of
        /// 2026-10-13 (`tasks/chores/2026-10-13-name-field-line-height.md`) closed it. With the focus the
        /// field draws the name itself, and its editor clipped at the title role's line: the tails of "y",
        /// "p" and "g" were cut flat. Measured then, the letters of "Gyp" without the focus and with it: 28.0
        /// and 24.7 pt at `.large`, 42.0 and 36.3 at `.accessibility3`, 48.0 and 41.3 at `.accessibility5`.
        /// The field is set with `ledgerFieldFont` now, and the known-issue wrapper is gone.
        @Test(
            "With the focus the day's name keeps its descenders",
            arguments: [
                DynamicTypeSize.large, .accessibility3, .accessibility5
            ]
        )
        func focus_doesNotCutTheDescenders(_ size: DynamicTypeSize) throws {
            let letters = try Self.lettersOfGyp(in: Self.field("Gyp"), at: size)
            #expect(letters.focused > letters.whole - 1, "\(size): \(letters.whole) pt, \(letters.focused) focused")
        }

        /// The same measure on the builder's `ProgramHeader`, which held its own one-line field in the same
        /// role and clipped by the same amounts. It holds a `NameField` now (the same chore).
        @Test(
            "With the focus the program's name keeps its descenders",
            arguments: [
                DynamicTypeSize.large, .accessibility3, .accessibility5
            ]
        )
        func focus_programHeader_doesNotCutTheDescenders(_ size: DynamicTypeSize) throws {
            let model = ProgramBuilderModel.Header(eyebrow: "", name: "Gyp", namePlaceholder: "Program name")
            let builders = try Self.lettersOfGyp(in: ProgramHeader(model: model) { _ in }, at: size)
            let days = try Self.lettersOfGyp(in: Self.field("Gyp"), at: size)
            #expect(
                builders.focused > builders.whole - 1,
                "\(size): \(builders.whole) pt, \(builders.focused) focused"
            )
            #expect(
                abs(builders.focused - days.focused) < 0.5 && abs(builders.whole - days.whole) < 0.5,
                "the two fields draw alike"
            )
        }

        /// The target is the blue marker behind the field. It holds every line of the drawn name, is 44 pt
        /// high at least, and UIKit finds the text field under a point of the first line and no text field
        /// under a point of the last: there the tap is the name field's own gesture.
        ///
        /// The chore of 2026-10-13: the field's line is `LedgerFont.fieldLineHeight` and no longer the
        /// title's, so its frame starts above the target, by half of what its line is higher (4.8 pt at
        /// `.large`, 7.1 at `.accessibility3`), where it started on the target's top.
        @Test("The name's target holds all its lines; the field itself stands on the first", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func target_holdsEveryLine(_ size: DynamicTypeSize) throws {
            let shown = try Shown(DayViewsState.longDay, at: size)
            defer { shown.close() }
            let (target, letters) = try (shown.target(), shown.letters())
            #expect(target.height >= 44 && target.width > 322, "\(target)")
            #expect(target.insetBy(dx: -0.5, dy: -0.5).contains(letters), "the name \(letters) in \(target)")
            let field = shown.field.convert(shown.field.bounds, to: shown.hosted.host.view)
            #expect(letters.height > field.height * 1.8, "the name wraps: \(letters.height) pt, a line \(field.height)")
            let higher = LedgerFont.fieldLineHeight - LedgerFont.Role.title.spec.lineHeight
            let above = higher * LedgerFont.scaledSize(.title, dynamicTypeSize: size) / 2
            #expect(
                abs(field.minY - (target.minY - above)) < 1 && abs(field.minX - target.minX) < 1,
                "\(field) in \(target), \(above) pt above it"
            )
            let view: UIView = shown.hosted.host.view
            let onTheFirstLine = view.hitTest(CGPoint(x: field.midX, y: field.midY), with: nil)
            let onTheLastLine = view.hitTest(CGPoint(x: letters.minX + 10, y: letters.maxY - 6), with: nil)
            #expect(Self.isInATextField(onTheFirstLine), "\(String(describing: onTheFirstLine))")
            #expect(!Self.isInATextField(onTheLastLine) && onTheLastLine != nil, "\(String(describing: onTheLastLine))")
        }

        static func isInATextField(_ view: UIView?) -> Bool {
            var next = view
            while let found = next {
                if found is UITextField {
                    return true
                }
                next = found.superview
            }
            return false
        }

        /// With the focus a name of several lines is one line: the target is as high as one line and what
        /// stands under it comes up. The field's own frame does not move (`DayEditorTextFieldTests`).
        @Test("With the focus a long name's target is one line high, and it is as it was when the focus leaves")
        func focus_longName_isOneLine() throws {
            let shown = try Shown(DayViewsState.longDay)
            defer { shown.close() }
            let before = try shown.target()
            try shown.focus(true)
            let with = try shown.target()
            let letters = try shown.letters()
            try shown.focus(false)
            let after = try shown.target()
            #expect(before.height > 2 * with.height && with.height >= 44, "\(before.height) pt, then \(with.height)")
            #expect(with.minY == before.minY && after == before, "\(before) \(with) \(after)")
            // The line runs out of the frame and is cut at the page's edge, as every field's is.
            #expect(letters.maxX <= with.maxX + 0.5 && letters.width > 300, "\(letters) in \(with)")
        }

        /// The stored name changes while the field has no focus: the drawn name is the new one, whole. While
        /// it has the focus the field keeps its draft and the text stays hidden; the blur draws the stored one.
        @Test("The drawn name follows the stored name without the focus, and after a blur")
        func storedName_changes_theDrawnNameFollows() throws {
            func fresh(_ name: String) throws -> PixelBuffer {
                let shown = try Shown(name)
                defer { shown.close() }
                return try shown.pixels()
            }
            let (first, second) = (DayViewsState.longDay, "Push")
            let shown = try Shown(first)
            defer { shown.close() }
            shown.hosted.show(Shown.view(second, .large, false))
            let isTheSecond = try shown.pixels() == fresh(second)
            #expect(isTheSecond, "without the focus the drawn name is the stored one")
            try shown.focus(true)
            shown.hosted.show(Shown.view(first, .large, false))
            #expect(shown.field.text == second, "the field keeps its draft")
            #expect(try shown.letters(hidingTheField: true).isNull, "the text is drawn under the field with the focus")
            try shown.focus(false)
            let isTheFirst = try shown.pixels() == fresh(first)
            #expect(isTheFirst, "after the blur the drawn name is the stored one, on its lines again")
        }

        /// While it is being edited the name is one line (ruling 15 accepts it). What the lifter then sees of
        /// a seed name, by round 1's measure, the field's own attributed text against its text rectangle:
        /// whole up to the default size, its end out of the field from `.xLarge` on 375 pt.
        @Test("While it is edited a seed name is whole on its one line up to the default size", arguments: [
            DynamicTypeSize.large, .xLarge, .accessibility3
        ])
        func whileEdited_seedNames_oneLine(_ size: DynamicTypeSize) throws {
            var cut: [String] = []
            for name in Field.seedNames {
                for width in ViewsSetting.widths {
                    let view = try Field.header(name) { _ in }.frame(width: width).environment(\.dynamicTypeSize, size)
                    let hosted = Hosted(view)
                    defer { hosted.close() }
                    let field = try #require(hosted.fields.first)
                    try #require(field.becomeFirstResponder())
                    hosted.settle()
                    let needs = try #require(field.attributedText).size().width
                    if needs > field.textRect(forBounds: field.bounds).width + 0.5 {
                        cut.append("\(Int(width)) pt: \(name)")
                    }
                }
            }
            let expected = [DynamicTypeSize.large: 0, .xLarge: 2, .accessibility3: 8]
            #expect(cut.count == expected[size], "\(cut)")
        }
    }
#endif
