@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// The role and text size of a drawing, and whether the icon's square is then a whole number of pixels wide:
/// only then is a mirror image the same picture read from its other end, pixel for pixel. At `.accessibility3`
/// the square's edge falls inside a pixel, and the lean alone is compared, to a pixel.
private nonisolated struct IconCell {
    let role: LedgerFont.Role
    let size: DynamicTypeSize
    let isWhole: Bool
}

extension RenderingSuites {
    /// Which icons turn round in a right-to-left layout (chore of 2026-10-12, item 2). A SwiftUI `Shape`
    /// mirrors under a right-to-left layout unless it says otherwise, so every `LedgerIcon` was drawn
    /// mirrored there, the set row's check mark among them. Apple's guidance (Human Interface Guidelines,
    /// "Right to left"): an icon that shows a direction of reading or of movement is flipped, and a check
    /// mark never is. Each icon is drawn here left to right and right to left, and the two are compared.
    @Suite("LedgerIcon direction", .tags(.design))
    struct LedgerIconDirectionTests {
        /// The icons that point along the reading direction, and so turn round with it: the arrow of
        /// "Start workout" (forward), a row's disclosure chevron (forward), and the swap button's pair of
        /// arrows, whose upper one points forward. The check mark and the steppers' signs stay as drawn.
        nonisolated static let mirrored: Set<LedgerIcon> = [.arrow, .chevron, .swap]

        /// An icon alone on the ground, at `role`'s size, in a layout of `direction`.
        static func drawn(
            _ icon: LedgerIcon, _ direction: LayoutDirection, as role: LedgerFont.Role, _ size: DynamicTypeSize
        ) throws -> PixelBuffer {
            let view = LedgerIconView(icon, sizedAs: role)
                .foregroundStyle(LedgerColor.ink)
                .background(LedgerColor.ground)
                .environment(\.layoutDirection, direction)
            return try #require(RenderedImage.render(view, dynamicTypeSize: size).flatMap(PixelBuffer.init))
        }

        /// The buffer's pixels with each row read from its other end.
        static func mirror(_ buffer: PixelBuffer) -> [Pixel] {
            (0 ..< buffer.height).flatMap { row in
                (0 ..< buffer.width).reversed().map { buffer.pixel(column: $0, row: row) }
            }
        }

        /// How many pixels of the two differ by more than the rounding of an edge's blend.
        static func differing(_ lhs: [Pixel], _ rhs: [Pixel]) -> Int {
            zip(lhs, rhs).count { $0.differs(from: $1, by: 8) }
        }

        /// How far right of the picture's middle the ink's weight lies, in pixels: an icon that points right
        /// is heavier there, and its mirror image as much heavier on the left.
        static func lean(_ buffer: PixelBuffer) -> Double {
            let ground = buffer.pixel(column: 0, row: 0)
            var weight = 0.0
            var moment = 0.0
            for row in 0 ..< buffer.height {
                for column in 0 ..< buffer.width {
                    let ink = abs(Double(buffer.pixel(column: column, row: row).red) - Double(ground.red))
                    weight += ink
                    moment += ink * (Double(column) + 0.5 - Double(buffer.width) / 2)
                }
            }
            return weight == 0 ? 0 : moment / weight
        }

        private nonisolated static let cells = [
            IconCell(role: .body, size: .large, isWhole: true), IconCell(role: .title, size: .large, isWhole: true),
            IconCell(role: .body, size: .accessibility3, isWhole: false)
        ]

        @Test(
            "Right to left an icon that points along the reading direction is mirrored, and no other icon moves",
            arguments: LedgerIcon.allCases
        )
        func icon_rightToLeft_isMirroredOnlyIfItPointsForward(_ icon: LedgerIcon) throws {
            for cell in Self.cells {
                let (role, size) = (cell.role, cell.size)
                let leftToRight = try Self.drawn(icon, .leftToRight, as: role, size)
                let rightToLeft = try Self.drawn(icon, .rightToLeft, as: role, size)
                let ground = leftToRight.pixel(column: 0, row: 0)
                let hasInk = leftToRight.inkedColumns(differingFrom: ground) != nil
                #expect(hasInk, "\(icon) \(role) \(size): nothing was drawn")
                #expect(rightToLeft.width == leftToRight.width && rightToLeft.height == leftToRight.height)
                if Self.mirrored.contains(icon) {
                    let moved = Self.differing(leftToRight.pixels, rightToLeft.pixels)
                    #expect(moved > 0, "control: \(icon) \(role) \(size) reads the same from both ends")
                    let leans = (Self.lean(leftToRight), Self.lean(rightToLeft))
                    let isOpposite = abs(leans.0 + leans.1) < (cell.isWhole ? 0.1 : 1)
                    #expect(isOpposite, "\(icon) \(role) \(size): leans \(leans), not mirrored")
                    if cell.isWhole {
                        let offMirror = Self.differing(Self.mirror(leftToRight), rightToLeft.pixels)
                        #expect(offMirror == 0, "\(icon) \(role) \(size): not the mirror image right to left")
                    }
                } else {
                    // Compared to a `Bool` first: inside `#expect` a failure would write both buffers out.
                    let isTheSame = rightToLeft == leftToRight
                    #expect(isTheSame, "\(icon) \(role) \(size): drawn otherwise right to left")
                }
            }
        }

        @Test("Control: the check mark reads otherwise from its other end, so a mirrored one would be seen")
        func check_isNotItsOwnMirrorImage() throws {
            let check = try Self.drawn(.check, .leftToRight, as: .title, .large)
            #expect(Self.differing(Self.mirror(check), check.pixels) > 20)
            // The steppers' signs are their own mirror images: fixed or mirrored, they are drawn the same.
            for sign in [LedgerIcon.minus, .plus] {
                let drawn = try Self.drawn(sign, .leftToRight, as: .title, .large)
                #expect(Self.differing(Self.mirror(drawn), drawn.pixels) == 0, "\(sign)")
            }
        }

        @Test("Every icon is in the table: a new one is given its direction here")
        func everyIcon_hasItsDirection() {
            #expect(Self.mirrored.isSubset(of: Set(LedgerIcon.allCases)))
            #expect(LedgerIcon.allCases.count == 6, "a new icon: say above whether it points forward")
            let turning = LedgerIcon.allCases.filter(\.mirrorsRightToLeft)
            #expect(turning == LedgerIcon.allCases.filter(Self.mirrored.contains))
        }
    }
}
