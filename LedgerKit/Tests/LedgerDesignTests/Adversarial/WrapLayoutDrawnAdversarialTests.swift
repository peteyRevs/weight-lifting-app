#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F11 S8 adversarial round 1, criterion 3, as SwiftUI runs the layout: pill buttons in rows of
        /// several widths at several text sizes, read back by their VoiceOver frames. Nothing stands outside
        /// the room the layout reported, no two pills overlap, right to left is the mirror image, and the
        /// layout holds its place inside other layouts.
        @Suite("Adversarial F11 S8 · WrapLayout, drawn", .tags(.design))
        struct WrapLayoutDrawnAdversarialTests {
            static let titles = WrapLayoutGallery.muscles + WrapLayoutGallery.equipment.dropFirst()
                + ["Posterior chain and everything else", "A"]

            /// The pills in a row `width` wide at the window's left edge, with a button under them: its top
            /// is where the layout said it ends.
            private static func frames(
                width: CGFloat,
                _ size: DynamicTypeSize,
                _ direction: LayoutDirection
            ) -> [CGRect] {
                let pills = VStack(alignment: .leading, spacing: 0) {
                    WrapLayout {
                        ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                            PillButton(title) {}
                        }
                    }
                    PillButton("END") {}
                }
                .frame(width: width, alignment: .leading)
                .environment(\.layoutDirection, direction)
                return HStack(spacing: 0) {
                    pills
                    Spacer(minLength: 0)
                }
                .accessibilityElements(SnapshotAppearance(.dark, size)).map(\.frame)
            }

            @Test(
                "At every width and text size each pill is a 44 pt target inside the layout, and none overlaps",
                arguments: [120, 200, 283, 402] as [CGFloat]
            )
            func pills_everyWidthAndSize_standInsideTheLayout(width: CGFloat) throws {
                for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
                    let found = Self.frames(width: width, size, .leftToRight)
                    #expect(found.count == Self.titles.count + 1, "\(width) \(size): \(found.count) elements")
                    let end = try #require(found.last)
                    let pills = Array(found.dropLast())
                    let slack: CGFloat = 0.01
                    for (place, pill) in pills.enumerated() {
                        let isInside = pill.minX >= -slack && pill.maxX <= width + slack && pill.minY >= -slack
                            && pill.maxY <= end.minY + slack
                        #expect(isInside, "\(width) \(size): pill \(place) at \(pill), the layout ends at \(end.minY)")
                        #expect(pill.height >= 44 - slack && pill.width >= min(44, width) - slack, "\(place): \(pill)")
                        let overlaps = pills.indices.contains { other in
                            other > place && pills[other].insetBy(dx: slack, dy: slack).intersects(pill)
                        }
                        #expect(!overlaps, "\(width) \(size): pill \(place) at \(pill) overlaps a later one")
                    }
                    // In reading order: each pill is right of the one before it, or on a lower row.
                    for place in pills.indices.dropFirst() {
                        let isAfter = pills[place].minX >= pills[place - 1].maxX - slack
                            || pills[place].minY >= pills[place - 1].maxY - slack
                        #expect(isAfter, "\(width) \(size): pill \(place) is not after pill \(place - 1)")
                    }
                }
            }

            @Test("Right to left every pill stands where the mirror puts it", arguments: [120, 283, 402] as [CGFloat])
            func rightToLeft_isTheMirrorImage(width: CGFloat) {
                for size in [DynamicTypeSize.large, .accessibility3] {
                    let leftToRight = Self.frames(width: width, size, .leftToRight).dropLast()
                    let rightToLeft = Self.frames(width: width, size, .rightToLeft).dropLast()
                    #expect(leftToRight.count == rightToLeft.count && leftToRight.count == Self.titles.count)
                    for (place, pair) in zip(leftToRight, rightToLeft).enumerated() {
                        let isMirrored = abs(pair.1.minX - (width - pair.0.maxX)) < 0.01
                            && abs(pair.1.minY - pair.0.minY) < 0.01 && abs(pair.1.width - pair.0.width) < 0.01
                        #expect(isMirrored, "\(width) \(size): pill \(place) \(pair.0) against \(pair.1)")
                    }
                }
            }

            private static let red = Color(.sRGB, red: 1, green: 0, blue: 0)
            private static let blue = Color(.sRGB, red: 0, green: 0, blue: 1)

            private static func extent(of color: Pixel, in buffer: PixelBuffer) -> CGRect? {
                var found = CGRect.null
                for row in 0 ..< buffer.height {
                    for column in 0 ..< buffer.width {
                        let isTheColor = !buffer.pixel(column: column, row: row).differs(from: color, by: 8)
                        found = isTheColor ? found.union(CGRect(x: column, y: row, width: 1, height: 1)) : found
                    }
                }
                return found.isNull ? nil : found
            }

            @Test("Padded, under another view and beside one, the layout places its children where it stands")
            func layout_insideOtherLayouts_keepsItsPlace() throws {
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.blue.frame(width: 60, height: 10)
                    Self.blue.frame(width: 60, height: 10)
                    Self.red.frame(width: 50, height: 20)
                }
                // 100 wide inside 15 pt of padding, under a 30 pt block: each child has a row, the red the third.
                let stacked = VStack(alignment: .leading, spacing: 0) {
                    Color.black.frame(width: 100, height: 30)
                    wrap
                }
                .padding(15)
                .background(Color.white)
                let image = try #require(RenderedImage.render(stacked, width: 130).flatMap(PixelBuffer.init))
                #expect(
                    image.width == 130 && image.height == 15 + 30 + 10 + 6 + 10 + 6 + 20 + 15,
                    "\(image.width) × \(image.height)"
                )
                #expect(Self.extent(of: Pixel(hex: 0xFF0000), in: image) == CGRect(x: 15, y: 77, width: 50, height: 20))

                // Beside a fixed block in a row 200 wide: the layout takes the 140 that are left.
                let beside = HStack(alignment: .top, spacing: 10) {
                    Color.black.frame(width: 50, height: 10)
                    wrap
                }
                .background(Color.white)
                let row = try #require(RenderedImage.render(beside, width: 200).flatMap(PixelBuffer.init))
                let blues = try #require(Self.extent(of: Pixel(hex: 0x0000FF), in: row))
                let reds = try #require(Self.extent(of: Pixel(hex: 0xFF0000), in: row))
                #expect(blues == CGRect(x: 60, y: 0, width: 128, height: 10), "\(blues)")
                #expect(reds == CGRect(x: 60, y: 16, width: 50, height: 20), "\(reds)")
                #expect(row.height == 36, "\(row.height)")
            }

            @Test(
                "A text longer than the row wraps inside it and nothing is drawn past the row's end, at any width",
                arguments: [60, 97, 150, 233] as [CGFloat]
            )
            func longText_everyWidth_staysInsideTheRow(width: CGFloat) throws {
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.blue.frame(width: 20, height: 10)
                    Text(verbatim: WrapLayoutGallery.long).foregroundStyle(Self.red)
                    Self.blue.frame(width: 20, height: 10)
                }
                .background(Color.white)
                // A row `width` wide with 40 pt of black beside it, so that a child reaching past it shows.
                let framed = wrap.frame(width: width, alignment: .leading)
                    .frame(width: width + 40, alignment: .leading)
                    .background(Color.black)
                let buffer = try #require(RenderedImage.render(framed, width: width + 40).flatMap(PixelBuffer.init))
                let reaches = (Int(width) ..< buffer.width).contains { column in
                    (0 ..< buffer.height).contains { buffer.pixel(column: column, row: $0) != Pixel(hex: 0x000000) }
                }
                #expect(buffer.width == Int(width) + 40)
                #expect(!reaches, "\(width): something is drawn past the row's end")
                let blues = try #require(Self.extent(of: Pixel(hex: 0x0000FF), in: buffer))
                #expect(blues.minY == 0 && Int(blues.maxY) == buffer.height, "\(width): \(blues) in \(buffer.height)")
            }
        }
    }
#endif
