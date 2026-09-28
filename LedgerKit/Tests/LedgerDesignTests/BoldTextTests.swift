@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Pete's decision (2026-09-27): with Bold Text on, every role moves one weight step up, as
/// system text does.
@Suite("BoldText", .tags(.design))
struct BoldTextTests {
    @Test("The Bold Text font is the role one weight step heavier, nothing else changed")
    func font_boldLegibility_isOneWeightStepUp() throws {
        for (role, size) in [(LedgerFont.Role.body, 15.0), (.label, 12.5), (.watchCaption, 17 / 1.5)] {
            let spec = role.spec
            let bold = LedgerFont.font(role, size: size, legibilityWeight: .bold)
            let stepped = LedgerFont.archivo(
                size: max(size, spec.minimumSize),
                weight: spec.weight + 100,
                width: spec.width
            )
            let actual = try #require(RenderedImage.render(Text("Upper A").font(bold)).flatMap(PixelBuffer.init))
            let expected = try #require(RenderedImage.render(Text("Upper A").font(stepped)).flatMap(PixelBuffer.init))
            #expect(actual == expected, "\(role)")
        }
    }

    @Test("ledgerFont reads Bold Text from the environment", arguments: [LedgerFont.Role.body, .numeralL])
    func ledgerFont_boldTextEnvironment_rendersHeavier(_ role: LedgerFont.Role) throws {
        func ink(_ weight: LegibilityWeight) throws -> Int {
            let view = Text("Upper A 185").ledgerFont(role).foregroundStyle(Color.white).background(Color.black)
                .environment(\.legibilityWeight, weight)
            return try #require(RenderedImage.render(view).flatMap(PixelBuffer.init)).pixels.count { $0.red > 0x80 }
        }
        #expect(try Double(ink(.bold)) > Double(ink(.regular)) * 1.05)
    }

    @Test("Bold Text never pushes a weight past the font's 900")
    func font_boldLegibility_staysWithinAxis() {
        #expect(LedgerFont.Role.allCases.allSatisfy { $0.spec.weight + LedgerFont.boldTextWeightStep <= 900 })
    }
}
