#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // The chore of 2026-10-13, gate G2: what the higher field and its caret reach, the two directions of
    // writing, and a text size that changes under the focus.

    extension NameFieldLineAdversarialTests {
        /// The Day editor's header under `name`, with the focus: the caret's box, the field's frame, where
        /// the tag's pill starts (the first thing drawn under the eyebrow when the field is hidden), and
        /// whether UIKit finds a text field under a point of the eyebrow or of the tag.
        struct Reach {
            let caret: CGRect
            let field: CGRect
            let tagTop: CGFloat
            let takesANeighboursTap: Bool
        }

        static func reach(under name: String, at size: DynamicTypeSize, _ weight: LegibilityWeight) throws -> Reach {
            let model = try DayViewsText(change: { path, text in path == "header.name" ? name : text })
                .content(ProgramPreview.dayEditor.dayEditorModel())
            let header = DayEditorHeader(model: model) { _ in }.environment(\.legibilityWeight, weight)
            let shown = try Shown(hosting: header, at: size)
            defer { shown.close() }
            try shown.focus(true)
            let caret = try shown.box { Int($0.blue) - Int($0.red) > 60 }
            let field = shown.field.convert(shown.field.bounds, to: shown.hosted.host.view)
            let bands = try Self.bands(of: shown.pixels(hidingTheField: true))
            let (eyebrow, tag) = try (#require(bands.first), #require(bands.dropFirst().first))
            let view: UIView = shown.hosted.host.view
            let points = [eyebrow.upperBound - 1, tag.lowerBound + 1, (tag.lowerBound + tag.upperBound) / 2]
            let taken = points.contains { down in
                let hit = view.hitTest(CGPoint(x: field.minX + 20, y: down), with: nil)
                return DayEditorViewsNameAdversarialTests.isInATextField(hit)
            }
            return Reach(caret: caret, field: field, tagTop: tag.lowerBound, takesANeighboursTap: taken)
        }

        /// The rows of a drawing at 3× that hold anything but the ground and the caret's blue, as bands, in
        /// points.
        static func bands(of drawn: PixelBuffer) -> [Range<CGFloat>] {
            let ground = drawn.pixels[0]
            var (bands, start): ([Range<CGFloat>], Int?) = ([], nil)
            for down in 0 ..< drawn.height {
                let row = drawn.pixels[down * drawn.width ..< (down + 1) * drawn.width]
                let isDrawn = row.contains { $0.differs(from: ground, by: 5) && Int($0.blue) - Int($0.red) <= 60 }
                if isDrawn, start == nil {
                    start = down
                } else if !isDrawn, let first = start {
                    bands.append(CGFloat(first) / 3 ..< CGFloat(down) / 3)
                    start = nil
                }
            }
            return bands
        }

        /// Measured, the room between the caret's foot and the tag's pill under a name of one line: 17.3 pt
        /// at `.large`, 7.3 at `.accessibility1`, 3.0 at `.accessibility3`, 2.0 at `.accessibility5`, the
        /// same with Bold Text. The field's frame ends where the caret does. Under the program's name the
        /// next thing drawn is 35 pt further at `.accessibility3` (45 pt at `.large`).
        @Test(
            "Under a name the caret and the field stay above the day's tag and take no neighbour's tap",
            arguments: [DynamicTypeSize.large, .accessibility1, .accessibility3, .accessibility5],
            [LegibilityWeight.regular, .bold]
        )
        func caret_staysAboveTheTag(_ size: DynamicTypeSize, _ weight: LegibilityWeight) throws {
            for name in ["A", "Ay"] {
                let found = try Self.reach(under: name, at: size, weight)
                #expect(!found.caret.isNull && found.caret.maxY <= found.tagTop - 1.5, "\(name): \(found)")
                #expect(found.field.maxY <= found.tagTop - 1.5, "\(name): the field reaches the tag: \(found)")
                #expect(!found.takesANeighboursTap, "\(name): a point of the eyebrow or the tag is the field's")
            }
        }

        /// **FINDING NF-2** (on `main` at `.accessibility5` by 1.3 pt; new at `.accessibility3`, and 8.7 pt
        /// at `.accessibility5`, with this chore). Up to `.accessibility1` the caret is clear by 7.3 pt.
        @Test(
            "With the draft emptied the caret stays above the day's tag (known from .accessibility3: NF-2)",
            arguments: [DynamicTypeSize.large, .accessibility1, .accessibility3, .accessibility5]
        )
        func emptyDraft_caretStaysAboveTheTag(_ size: DynamicTypeSize) throws {
            let found = try Self.reach(under: "", at: size, .regular)
            try #require(!found.caret.isNull, "no caret is drawn")
            #expect(found.caret.maxY <= found.tagTop, "the caret ends at \(found.caret.maxY), \(found)")
        }

        /// How far the name's ink moves sideways when the focus comes.
        static func sideways(_ view: some View, isRightToLeft: Bool) throws -> CGFloat {
            let set = view.environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            let shown = try Shown(hosting: set, at: .large)
            defer { shown.close() }
            let idle = try shown.letters()
            try shown.focus(true)
            return try shown.letters().minX - idle.minX
        }

        /// **FINDING NF-3.** New in the builder with this chore; the Day editor's since S10. The second case
        /// needs no right-to-left language in the app: a program named in Hebrew or Arabic is enough.
        @Test(
            "When the focus comes a name does not jump across the field (known: NF-3)",
            arguments: Place.allCases, [true, false]
        )
        func focus_doesNotJumpAcross(_ place: Place, _ isRightToLeft: Bool) throws {
            let name = isRightToLeft ? "Upper A" : "תוכנית עליון"
            let across = try Self.sideways(place.view(name), isRightToLeft: isRightToLeft)
            #expect(abs(across) < 0.34, "\(name): \(across) pt")
        }

        @Test("A name in the layout's own direction stays where it is when the focus comes", arguments: Place.allCases)
        func focus_ownDirection_doesNotJump(_ place: Place) throws {
            let hebrew = try Self.sideways(place.view("תוכנית עליון"), isRightToLeft: true)
            let latin = try Self.sideways(place.view("Upper A"), isRightToLeft: false)
            #expect(abs(hebrew) < 0.34 && abs(latin) < 0.34, "Hebrew \(hebrew) pt, Latin \(latin) pt")
        }

        /// The guide reads the text size from the environment: a size that changes while the name is edited
        /// must leave the field where a field first drawn at that size stands.
        @Test("A text size that changes under the focus leaves the field as one first drawn at that size", arguments: [
            [DynamicTypeSize.large, .accessibility3], [.accessibility5, .large], [.large, .accessibility5]
        ])
        func textSize_changesUnderTheFocus(_ sizes: [DynamicTypeSize]) throws {
            let (first, second) = (sizes[0], sizes[1])
            let (changed, fresh) = try (
                Shown("Gyp", at: first, isMarked: false),
                Shown("Gyp", at: second, isMarked: false)
            )
            defer {
                changed.close()
                fresh.close()
            }
            try changed.focus(true)
            changed.hosted.show(Shown.view("Gyp", second, false, isMarked: false))
            changed.hosted.settle()
            try fresh.focus(true)
            #expect(changed.field.isFirstResponder, "the field lost the focus")
            #expect(try changed.letters() == fresh.letters())
            let frames = [changed, fresh].map { $0.field.convert($0.field.bounds, to: $0.hosted.host.view) }
            #expect(frames[0] == frames[1], "\(frames)")
        }
    }
#endif
