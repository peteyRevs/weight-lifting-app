import CoreGraphics
@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// F11 S8 criterion 3, the arithmetic: where `WrapLayout` stands children of given sizes, and the size it
/// reports for them. The layout's two entry points both go through `arrangement(of:in:)`, so the size
/// reported is the size used by construction; `WrapLayoutRenderingTests` shows the same on drawn views.
@Suite("WrapLayout", .tags(.design))
nonisolated struct WrapLayoutTests {
    static let layout = WrapLayout(spacing: 8, lineSpacing: 6)

    static func sizes(_ widths: CGFloat..., height: CGFloat = 20) -> [CGSize] {
        widths.map { CGSize(width: $0, height: height) }
    }

    static func rect(_ across: CGFloat, _ down: CGFloat, _ width: CGFloat, _ height: CGFloat = 20) -> CGRect {
        CGRect(x: across, y: down, width: width, height: height)
    }

    @Test("No child takes no room, whatever the width")
    func noChild_takesNoRoom() {
        for width in [nil, 0, 100, CGFloat.infinity] {
            let arrangement = Self.layout.arrangement(of: [], in: width)
            #expect(arrangement.size == .zero)
            #expect(arrangement.frames.isEmpty)
        }
    }

    @Test("One child stands at the start, and the layout is its size")
    func oneChild_standsAtTheStart() {
        let arrangement = Self.layout.arrangement(of: Self.sizes(40), in: 100)
        #expect(arrangement.frames == [Self.rect(0, 0, 40)])
        #expect(arrangement.size == CGSize(width: 40, height: 20))
    }

    @Test("Children that fit run along one row, the spacing between them")
    func childrenThatFit_runAlongOneRow() {
        let arrangement = Self.layout.arrangement(of: Self.sizes(30, 20, 26), in: 100)
        #expect(arrangement.frames == [Self.rect(0, 0, 30), Self.rect(38, 0, 20), Self.rect(66, 0, 26)])
        #expect(arrangement.size == CGSize(width: 92, height: 20))
    }

    @Test("A child that does not fit beside the others starts the next row; the layout is as wide as its widest row")
    func childThatDoesNotFit_startsTheNextRow() {
        let arrangement = Self.layout.arrangement(of: Self.sizes(30, 20, 50, 40, 70), in: 100)
        #expect(arrangement.frames == [
            Self.rect(0, 0, 30), Self.rect(38, 0, 20), Self.rect(0, 26, 50), Self.rect(58, 26, 40),
            Self.rect(0, 52, 70)
        ])
        #expect(arrangement.size == CGSize(width: 98, height: 72))
    }

    @Test("A child that ends exactly at the row's end stays on the row; a point more wraps it")
    func childEndingAtTheEdge_stays() {
        #expect(Self.layout.arrangement(of: Self.sizes(46, 46), in: 100).frames.map(\.minY) == [0, 0])
        #expect(Self.layout.arrangement(of: Self.sizes(46, 47), in: 100).frames.map(\.minY) == [0, 26])
    }

    @Test("A child as wide as the row, or wider, has a row to itself, and the next child wraps")
    func childAsWideAsTheRow_hasARowToItself() {
        let arrangement = Self.layout.arrangement(of: Self.sizes(30, 100, 30), in: 100)
        #expect(arrangement.frames == [Self.rect(0, 0, 30), Self.rect(0, 26, 100), Self.rect(0, 52, 30)])
        #expect(arrangement.size == CGSize(width: 100, height: 72))
        // The first of a row always stays, whatever its width: nothing is dropped and nothing loops.
        let wider = Self.layout.arrangement(of: Self.sizes(130), in: 100)
        #expect(wider.frames == [Self.rect(0, 0, 130)])
    }

    @Test("With no width, or an unbounded one, everything stands on one row")
    func noWidth_isOneRow() {
        for width in [nil, CGFloat.infinity] {
            let arrangement = Self.layout.arrangement(of: Self.sizes(80, 80, 80), in: width)
            #expect(arrangement.frames.map(\.minX) == [0, 88, 176])
            #expect(arrangement.size == CGSize(width: 256, height: 20))
        }
    }

    @Test("In a row of no width each child has a row to itself, at its own size: nothing is dropped")
    func zeroWidth_isOneChildARow() {
        let arrangement = Self.layout.arrangement(of: Self.sizes(40, 30, 0), in: 0)
        #expect(arrangement.frames == [Self.rect(0, 0, 40), Self.rect(0, 26, 30), Self.rect(0, 52, 0)])
        #expect(arrangement.size == CGSize(width: 40, height: 72))
    }

    @Test("A row is as high as its highest child, and the others are centred on it")
    func rowOfMixedHeights_isCentred() {
        let sizes = [CGSize(width: 30, height: 10), CGSize(width: 30, height: 40), CGSize(width: 60, height: 20)]
        let arrangement = Self.layout.arrangement(of: sizes, in: 100)
        #expect(arrangement.frames == [
            Self.rect(0, 15, 30, 10), Self.rect(38, 0, 30, 40), Self.rect(0, 46, 60, 20)
        ])
        #expect(arrangement.size == CGSize(width: 68, height: 66))
    }

    @Test("The size reported is exactly the room the children take, at any width", arguments: [
        30, 59, 60, 100, 137, 1000
    ])
    func reportedSize_isTheRoomTheChildrenTake(width: CGFloat) {
        let sizes = [18, 60, 25, 44, 9, 31, 52, 60, 12].enumerated().map { place, childWidth in
            CGSize(width: CGFloat(childWidth), height: CGFloat(10 + place % 3 * 7))
        }
        let arrangement = Self.layout.arrangement(of: sizes, in: width)
        let union = arrangement.frames.reduce(CGRect.null) { $0.union($1) }
        #expect(arrangement.frames.count == sizes.count)
        #expect(union.minX == 0 && union.minY == 0)
        #expect(union.size == arrangement.size)
        #expect(arrangement.frames.map(\.size) == sizes, "no child is resized")
        #expect(arrangement.size.width <= max(width, 60), "only a child wider than the row passes its end")
        // No two children overlap, and each keeps the spacing from the one before it on its row.
        for (place, frame) in arrangement.frames.enumerated().dropFirst() {
            let before = arrangement.frames[place - 1]
            let isBeside = frame.minX == before.maxX + 8 && frame.intersects(before.insetBy(dx: -9, dy: 0))
            let isBelow = frame.minX == 0 && frame.minY >= before.minY
            #expect(isBeside || isBelow, "child \(place) at \(frame) after \(before)")
        }
    }
}

#if os(iOS)
    extension RenderingSuites {
        /// F11 S8 criterion 3, drawn: the layout as SwiftUI runs it. Children are coloured blocks of fixed sizes,
        /// found again by their colour.
        @Suite("WrapLayout, drawn", .tags(.design))
        struct WrapLayoutRenderingTests {
            static let red = Pixel(hex: 0xFF0000)
            static let blue = Pixel(hex: 0x0000FF)

            /// Pure sRGB red and blue: SwiftUI's `.red` and `.blue` are the system's, which are neither.
            static let redFill = Color(.sRGB, red: 1, green: 0, blue: 0)
            static let blueFill = Color(.sRGB, red: 0, green: 0, blue: 1)

            private static func block(_ color: Color, _ width: CGFloat, _ height: CGFloat = 10) -> some View {
                color.frame(width: width, height: height)
            }

            private static func drawn(_ view: some View, width: CGFloat? = 100) throws -> PixelBuffer {
                try #require(RenderedImage.render(view, width: width).flatMap(PixelBuffer.init))
            }

            /// The columns and the rows that hold a pixel of `color`.
            private static func extent(
                of color: Pixel,
                in buffer: PixelBuffer
            ) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>)? {
                var columns: [Int] = []
                var rows: [Int] = []
                for row in 0 ..< buffer.height {
                    for column in 0 ..< buffer.width where !buffer.pixel(column: column, row: row).differs(
                        from: color,
                        by: 8
                    ) {
                        columns.append(column)
                        rows.append(row)
                    }
                }
                guard let left = columns.min(), let right = columns.max(), let top = rows.min(),
                      let bottom = rows.max()
                else {
                    return nil
                }
                return (left ... right, top ... bottom)
            }

            @Test("The view is as big as the rows it holds: the size reported is the size used")
            func drawnSize_isTheSizeOfItsRows() throws {
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.block(Self.redFill, 60)
                    Self.block(Self.redFill, 30)
                    Self.block(Self.blueFill, 50, 20)
                }
                let buffer = try Self.drawn(wrap)
                #expect(buffer.width == 98 && buffer.height == 36, "\(buffer.width) × \(buffer.height)")
                let second = try #require(Self.extent(of: Self.blue, in: buffer))
                #expect(second.columns == 0 ... 49 && second.rows == 16 ... 35, "\(second)")
                let unbounded = try Self.drawn(wrap, width: nil)
                #expect(unbounded.width == 60 + 8 + 30 + 8 + 50 && unbounded.height == 20, "one row without a width")
            }

            @Test(
                "Left to right the first child stands at the left; right to left, at the right, as does each row"
            )
            func rightToLeft_runsFromTheRight() throws {
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.block(Self.redFill, 30)
                    Self.block(Self.blueFill, 40)
                    Self.block(Self.blueFill, 90)
                }
                .frame(width: 100, alignment: .leading)
                let leftToRight = try Self.drawn(wrap.environment(\.layoutDirection, .leftToRight))
                let rightToLeft = try Self.drawn(wrap.environment(\.layoutDirection, .rightToLeft))
                let first = try #require(Self.extent(of: Self.red, in: leftToRight))
                let mirrored = try #require(Self.extent(of: Self.red, in: rightToLeft))
                #expect(first.columns == 0 ... 29, "\(first)")
                #expect(mirrored.columns == 70 ... 99, "\(mirrored)")
                #expect(first.rows == mirrored.rows)
                // The second row's block starts at the right edge too.
                #expect(rightToLeft.pixel(column: 99, row: 20) == Self.blue)
                #expect(rightToLeft.pixel(column: 5, row: 20) != Self.blue)
                #expect(leftToRight.pixel(column: 5, row: 20) == Self.blue)
            }

            @Test("A child wider than the row is given the row's width, on a row of its own")
            func childWiderThanTheRow_getsTheRowsWidth() throws {
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.block(Self.blueFill, 30)
                    // It would be 300 pt wide, and takes what it is offered.
                    Self.redFill.frame(idealWidth: 300, maxWidth: 300).frame(height: 10)
                    Self.block(Self.blueFill, 30)
                }
                let buffer = try Self.drawn(wrap)
                #expect(
                    buffer.width == 100 && buffer.height == 10 + 6 + 10 + 6 + 10,
                    "\(buffer.width) × \(buffer.height)"
                )
                let wide = try #require(Self.extent(of: Self.red, in: buffer))
                #expect(wide.columns == 0 ... 99 && wide.rows == 16 ... 25, "\(wide)")
            }

            @Test("A long label wraps inside the row's width, and the row is as high as the wrapped label")
            func longPill_wrapsInsideTheRow() throws {
                let oneLine = try Self.drawn(WrapLayout { PillButton("Legs") {} }, width: 200)
                let wrap = WrapLayout { PillButton(WrapLayoutGallery.long) {} }
                let buffer = try Self.drawn(wrap, width: 200)
                #expect(buffer.width <= 200, "\(buffer.width)")
                #expect(buffer.height > oneLine.height, "\(buffer.height) against \(oneLine.height)")
            }

            @Test("Asked for its smallest size (a proposal of zero) with children, it has no width and a row a child")
            func zeroProposal_withChildren_isOneChildARow() throws {
                let probe = ZeroProbe()
                let wrap = WrapLayout(spacing: 8, lineSpacing: 6) {
                    Self.block(Self.redFill, 30)
                    Self.block(Self.blueFill, 40, 20)
                }
                _ = try Self.drawn(ZeroProbeLayout(probe: probe) { wrap })
                #expect(probe.sizes == [CGSize(width: 0, height: 10 + 6 + 20)], "\(probe.sizes)")
            }

            @Test("No child and one child draw: nothing, and the child alone")
            func noChildAndOneChild_draw() throws {
                let one = try Self.drawn(WrapLayout { Self.block(Self.redFill, 30) })
                #expect(one.width == 30 && one.height == 10)
                // `ImageRenderer` gives no image for a view of no size.
                let none = RenderedImage.render(WrapLayout {}, width: 100)
                #expect(none == nil || none?.width == 0 || none?.height == 0)
                let padded = try Self.drawn(WrapLayout {}.padding(5).background(Self.redFill))
                #expect(padded.width == 10 && padded.height == 10, "an empty layout takes no room of its own")
            }
        }
    }

    /// What `ZeroProbeLayout` was answered. A layout's methods are nonisolated; SwiftUI calls them on the main
    /// actor, where the test reads the answer afterwards.
    final nonisolated class ZeroProbe: @unchecked Sendable {
        nonisolated(unsafe) var sizes: [CGSize] = []
    }

    /// Asks its one child for its size at a proposal of zero, as SwiftUI does for a smallest size, and keeps
    /// the answer; otherwise it is its child.
    nonisolated struct ZeroProbeLayout: Layout {
        let probe: ZeroProbe

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            probe.sizes = subviews.map { $0.sizeThatFits(.zero) }
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            subviews.first?.place(at: bounds.origin, proposal: proposal)
        }
    }
#endif
