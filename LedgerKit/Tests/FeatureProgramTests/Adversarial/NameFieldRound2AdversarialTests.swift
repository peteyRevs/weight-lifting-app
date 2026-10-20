#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    // The chore of 2026-10-13, gate G2, round 2: the two new pieces of fix round 1, the field's alignment by
    // the layout and the unseen one-line label under the name.

    extension NameFieldLineAdversarialTests {
        /// How much ink stands in each column of the name's drawing at 3×, from its first inked column.
        static func columns(of drawn: PixelBuffer) -> [Int] {
            var sums = [Int](repeating: 0, count: drawn.width)
            // Row by row through the storage, as `Shown.box(in:_:)`: unoptimized, an index and a division per
            // pixel were most of a case's time.
            drawn.pixels.withUnsafeBufferPointer { pixels in
                for down in 0 ..< drawn.height {
                    let row = down * drawn.width
                    for across in 0 ..< drawn.width {
                        let pixel = pixels[row + across]
                        if pixel.red > 120, pixel.green > 120 {
                            sums[across] += 1
                        }
                    }
                }
            }
            guard let first = sums.firstIndex(where: { $0 > 0 }), let last = sums.lastIndex(where: { $0 > 0 }) else {
                return []
            }
            return Array(sums[first ... last])
        }

        /// How far apart two column profiles are, as a share of the first one's ink: 0 for the same words in
        /// the same order, far more for the same words in another order.
        static func distance(_ first: [Int], _ second: [Int]) -> Double {
            let count = max(first.count, second.count)
            let padded = { (row: [Int]) in row + [Int](repeating: 0, count: count - row.count) }
            let apart = zip(padded(first), padded(second)).map { abs($0 - $1) }.reduce(0, +)
            return Double(apart) / Double(max(first.reduce(0, +), 1))
        }

        static func shown(
            _ name: String,
            _ place: Place,
            _ size: DynamicTypeSize,
            isRightToLeft: Bool
        ) throws -> Shown {
            let view = place.view(name).environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            return try Shown(hosting: view, at: size)
        }

        /// `.multilineTextAlignment(strategy: .layoutBased)` moves where the field's line starts; it must not
        /// change the order the words of a name of two scripts stand in, nor where the line starts and ends.
        /// The measure is the ink of each column. Measured: a name that mixes the scripts is drawn in the same
        /// order with the focus and without, either way of writing (the text and the field both take the
        /// paragraph's direction from its first letter, so "Upper עליון" and "עליון Upper" are even drawn
        /// alike). The control is two Latin words in the other order, which the measure must see. An Arabic
        /// name's ink ends up to 1.7 pt short of where the text's does at the accessibility sizes: the field
        /// shapes it a little narrower, at its trailing end, and its leading edge stays.
        @Test(
            "With the focus a name of two scripts keeps its words' order and its edges, either way of writing",
            arguments: Place.allCases, NameFieldLineAdversarialTests.sizes
        )
        func focus_mixedScripts_keepTheirOrder(_ place: Place, _ size: DynamicTypeSize) throws {
            for isRightToLeft in [false, true] {
                for name in ["Upper עליון", "עליון Upper", "Day 1 יום", "يوم Push 2"] {
                    let shown = try Self.shown(name, place, size, isRightToLeft: isRightToLeft)
                    defer { shown.close() }
                    // One drawing each, measured twice.
                    let before = try shown.pixels()
                    let (idle, idleBox) = (Self.columns(of: before), shown.letters(in: before))
                    try shown.focus(true)
                    let after = try shown.pixels()
                    let (focused, focusedBox) = (Self.columns(of: after), shown.letters(in: after))
                    let apart = Self.distance(idle, focused)
                    let edges = abs(focusedBox.minX - idleBox.minX) < 2 && abs(focusedBox.maxX - idleBox.maxX) < 2
                    #expect(apart < 0.15 && edges, "\(isRightToLeft) \(name): \(apart); \(idleBox) → \(focusedBox)")
                }
                let swapped = try ["Upper Lower", "Lower Upper"].map { name in
                    let shown = try Self.shown(name, place, size, isRightToLeft: isRightToLeft)
                    defer { shown.close() }
                    return try Self.columns(of: shown.pixels())
                }
                let control = Self.distance(swapped[0], swapped[1])
                #expect(control > 0.15, "the measure does not see two words swapped: \(control)")
            }
        }

        /// NF-3 at `.large` is `focus_doesNotJumpAcross`; here the two accessibility sizes. (A name longer
        /// than the field while edited is left out: its visible part is where UIKit scrolls it.)
        @Test(
            "At the accessibility sizes a name against the layout's direction does not jump across either",
            arguments: Place.allCases, TestSweep.sizes([.accessibility3, .accessibility5])
        )
        func focus_doesNotJumpAcross_atAccessibilitySizes(_ place: Place, _ size: DynamicTypeSize) throws {
            for (name, isRightToLeft) in [
                ("Upper A", true),
                ("תוכנית עליון", false),
                ("Upper עליון", true)
            ] {
                let shown = try Self.shown(name, place, size, isRightToLeft: isRightToLeft)
                defer { shown.close() }
                let idle = try shown.letters()
                try shown.focus(true)
                let focused = try shown.letters()
                // The leading edge: the right one on a right-to-left layout.
                let across = isRightToLeft ? focused.maxX - idle.maxX : focused.minX - idle.minX
                // Measured: 0 to 1.3 pt (the field draws the last letter's ink a pixel or four short).
                #expect(abs(across) < 1.5, "\(name), \(isRightToLeft): \(across) pt")
            }
        }

        static let longLabel = "A label far longer than any phone's line, as a translation of it might be"

        /// The unseen label is as wide as nothing: a label longer than the screen changes no pixel and no
        /// frame of a name, short or long, either way of writing, and VoiceOver reads it only as the field's
        /// label (the field itself is no element to the hosted reader, `ProgramTextFieldTests`).
        @Test(
            "A long label widens, moves and reads nothing, either way of writing",
            arguments: [DynamicTypeSize.large, .accessibility5]
        )
        func longLabel_changesNothing(_ size: DynamicTypeSize) throws {
            for isRightToLeft in [false, true] {
                for name in ["A", ProgramPreviewData.longName] {
                    func drawn(_ label: String) throws -> (PixelBuffer, CGRect) {
                        let view = NameField(label: label, name: name) { _ in }
                            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
                        let shown = try Shown(hosting: view, at: size)
                        defer { shown.close() }
                        return try (shown.pixels(), shown.field.convert(shown.field.bounds, to: shown.hosted.host.view))
                    }
                    let (short, long) = try (drawn("x"), drawn(Self.longLabel))
                    #expect(short.0 == long.0, "\(isRightToLeft) \(name.prefix(12)): the pictures differ")
                    #expect(short.1 == long.1, "\(isRightToLeft) \(name.prefix(12)): \(short.1), \(long.1)")
                }
            }
            let model = ProgramBuilderModel.Header(eyebrow: "MY PROGRAM", name: "", namePlaceholder: Self.longLabel)
            let stops = ProgramHeader(model: model) { _ in }.stops(SnapshotAppearance(.light, size))
            #expect(stops == [.heading("MY PROGRAM")], "\(stops)")
            #expect(NameField(label: Self.longLabel, name: "") { _ in }.stops(SnapshotAppearance(.light, size)).isEmpty)
        }

        /// The builder's header with an empty name keeps one line of the title, as the Day editor's does.
        @Test("With the draft emptied the builder's header is as high as under one letter", arguments: sizes)
        func emptyProgramName_keepsALine(_ size: DynamicTypeSize) throws {
            func height(_ name: String) throws -> CGFloat {
                let header = Place.program.view(name)
                return try CGFloat(ProgramDrawing.pixels(of: header.environment(\.dynamicTypeSize, size), .dark).height)
            }
            let (empty, letter) = try (height(""), height("A"))
            #expect(abs(empty - letter) <= 1, "empty \(empty) pt, one letter \(letter) pt")
        }
    }
#endif
