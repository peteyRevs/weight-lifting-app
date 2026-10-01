#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F06 slice 3, adversarial close-out: the edges of fix round 1 (`a19d20a`) outside the sheet. The
        /// progress bar's non-positive segments anywhere in the bar; the stat unit's size at every text
        /// size, with Bold Text, and an empty unit.
        @Suite("Slice 3 close-out: bar and tile (adversarial, slice 3 close-out round)", .tags(.design))
        struct Slice3CloseoutAdversarialTests {
            // MARK: S3-3: non-positive segments anywhere in the bar

            @Test("Non-positive segments anywhere leave no gap and no ink; all non-positive draws nothing")
            func progressSegments_nonPositiveAnywhere_leaveNoGap() throws {
                let gap = Int(ProgressSegments.gap)
                let trailing = try Slice3LayoutAdversarialTests.inkedRuns(
                    Slice3LayoutAdversarialTests.bar([0, 0, 3, 0], width: 100)
                )
                #expect(trailing == [0 ... 99], "[0, 0, 3, 0]: \(trailing)")
                let mixed = try Slice3LayoutAdversarialTests.inkedRuns(
                    Slice3LayoutAdversarialTests.bar([-5, 3, 0, Int.min, 3, -1], width: 100)
                )
                #expect(mixed.count == 2, "\(mixed)")
                if mixed.count == 2 {
                    #expect(mixed[0].lowerBound == 0 && mixed[1].upperBound == 99, "\(mixed)")
                    #expect(mixed[1].lowerBound - mixed[0].upperBound - 1 == gap, "\(mixed)")
                }
                for lengths in [[0], [0, 0, 0], [-1, Int.min]] {
                    let runs = try Slice3LayoutAdversarialTests.inkedRuns(
                        Slice3LayoutAdversarialTests.bar(lengths, width: 100)
                    )
                    #expect(runs.isEmpty, "\(lengths): \(runs)")
                }
            }

            @Test("VoiceOver's frame of the bar is the full width whatever the non-positive segments")
            func progressSegments_nonPositive_fullWidthElement() throws {
                for lengths in [[0, 3], [3, 0], [0, 0], [-2, 3, 0, 3]] {
                    let bar = ProgressSegments(
                        lengths.map { ProgressSegment(length: $0, state: .done) },
                        label: "Workout progress",
                        value: "Exercise 1 of 2"
                    )
                    let elements = bar.accessibilityElements()
                    let element = try #require(elements.first, "\(lengths)")
                    #expect(elements.count == 1, "\(lengths): \(elements)")
                    #expect(
                        element.frame.minX == 0 && element.frame.width == SnapshotConfig.phoneWidth,
                        "\(lengths): \(element.frame)"
                    )
                }
            }

            // MARK: R3-S2: the unit is 19/34 of the value at every text size, on its baseline

            /// A tile whose value and unit are both "8", on black, at 3×: the two runs of ink, left to right.
            static func eights(_ size: DynamicTypeSize, bold: Bool) throws -> (value: InkBox, unit: InkBox) {
                let tile = StatTile(value: "8", unit: "8", caption: " ")
                    .fixedSize()
                    .padding(8)
                    .background(Color.black)
                    .environment(\.legibilityWeight, bold ? .bold : .regular)
                let buffer = try #require(Probe.buffer(tile, scale: 3, dynamicTypeSize: size))
                let boxes = InkBox.runs(in: buffer)
                try #require(boxes.count == 2, "\(size): \(boxes.count) runs of ink")
                return (boxes[0], boxes[1])
            }

            @Test(
                "The unit's digits are 19/34 of the value's and share its baseline, xSmall to AX5, bold too",
                arguments: Slice3CloseoutSheetAdversarialTests.textSizes
            )
            func statTile_unit_isNineteenThirtyFourthsOnTheBaseline(_ size: DynamicTypeSize) throws {
                for bold in [false, true] {
                    let cell = "\(size)\(bold ? " bold" : "")"
                    let (value, unit) = try Self.eights(size, bold: bold)
                    let ratio = Double(unit.height) / Double(value.height)
                    #expect(
                        abs(ratio - 19.0 / 34) < 0.03,
                        "\(cell): unit \(unit.height) px, value \(value.height) px, ratio \(ratio)"
                    )
                    #expect(
                        abs(unit.bottom - value.bottom) <= 2,
                        "\(cell): unit bottom \(unit.bottom), value bottom \(value.bottom)"
                    )
                }
            }

            @Test("An empty unit draws and reads exactly as no unit", arguments: [
                SnapshotAppearance(.light, .large), SnapshotAppearance(.dark, .accessibility3)
            ])
            func statTile_emptyUnit_isNoUnit(_ appearance: SnapshotAppearance) throws {
                let none = StatTile(value: "41.2", caption: "lb moved", delta: "+8%")
                let empty = StatTile(value: "41.2", unit: "", caption: "lb moved", delta: "+8%")
                func pixels(_ tile: StatTile) throws -> PixelBuffer {
                    try #require(Probe.buffer(
                        tile.frame(width: 180).background(LedgerColor.ground),
                        dynamicTypeSize: appearance.dynamicTypeSize,
                        colorScheme: appearance.colorScheme
                    ))
                }
                #expect(try pixels(none) == pixels(empty))
                #expect(none.accessibilityElements(appearance).map(\.label)
                    == empty.accessibilityElements(appearance).map(\.label))
            }
        }
    }

    /// One run of ink columns and its vertical extent, in pixels.
    struct InkBox: CustomStringConvertible {
        var left, right, top, bottom: Int
        var height: Int {
            bottom - top + 1
        }

        var description: String {
            "x \(left)…\(right), y \(top)…\(bottom)"
        }

        /// Every pixel brighter than a quarter on black counts as ink.
        static func isInk(_ pixel: Pixel) -> Bool {
            max(pixel.red, pixel.green, pixel.blue) > 64
        }

        static func runs(in buffer: PixelBuffer) -> [InkBox] {
            var boxes: [InkBox] = []
            for column in 0 ..< buffer.width {
                let rows = (0 ..< buffer.height).filter { isInk(buffer.pixel(column: column, row: $0)) }
                guard let high = rows.first, let low = rows.last else { continue }
                if var last = boxes.last, last.right == column - 1 {
                    last.right = column
                    last.top = min(last.top, high)
                    last.bottom = max(last.bottom, low)
                    boxes[boxes.count - 1] = last
                } else {
                    boxes.append(InkBox(left: column, right: column, top: high, bottom: low))
                }
            }
            return boxes
        }
    }
#endif
