@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Review R3-N6, landed with R3-S2: the unit after a stat value is a run of its own, so the
    /// numerals' tight tracking (−0.03 em) must not reach it. The run carries `bodyLight`'s tracking.
    @Suite("StatTileValueLine", .tags(.design))
    struct StatTileValueLineTests {
        @Test("The unit run keeps its own role's tracking, not the numerals'")
        func valueLine_unitRun_keepsItsOwnTracking() throws {
            let valueSize: CGFloat = 34
            let line = StatTile.valueLine("195", unit: "kg lifted", valueSize: valueSize, legibilityWeight: nil)
            let unit = try #require(line.runs.last)
            #expect(unit.tracking == LedgerFont.Role.bodyLight.spec.tracking * valueSize * StatTile.unitEms)
            // The same line with the unit left to the numerals' tracking: about 1 pt less after each of
            // its nine characters.
            var inherited = line
            inherited[unit.range].tracking = nil
            let ownWidth = try inkedWidth(line)
            let inheritedWidth = try inkedWidth(inherited)
            #expect(
                ownWidth >= inheritedWidth + 4,
                "the line is \(ownWidth) px wide, \(inheritedWidth) px with the numerals' tracking on the unit"
            )
        }

        private func inkedWidth(_ line: AttributedString) throws -> Int {
            let view = Text(line).ledgerFont(.numeralXL).foregroundStyle(LedgerColor.ink)
                .padding(LedgerSpacing.s)
                .background(LedgerColor.ground)
            let pixels = try #require(RenderedImage.render(view).flatMap(PixelBuffer.init))
            return try #require(pixels.inkedColumns(differingFrom: Pixel(hex: 0x0B0B0D))).count
        }
    }
}
