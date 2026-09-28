@testable import LedgerDesign
import SwiftUI
import Testing

/// F06 criterion 2: every colour token resolves to the spec's sRGB value (docs/product-spec.md
/// §8.1–§8.3). Expected values are copied from the spec, not from `LedgerRGBA`.
@Suite("TokenValues", .tags(.design))
struct TokenValueTests {
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let hex: UInt32
        let alpha: Double

        init(_ name: String, _ color: Color, _ hex: UInt32, _ alpha: Double = 1) {
            self.name = name
            self.color = color
            self.hex = hex
            self.alpha = alpha
        }

        var testDescription: String {
            name
        }
    }

    nonisolated static let dark: [Case] = [
        Case("ground", LedgerColor.ground, 0x0B0B0D),
        Case("surface", LedgerColor.surface, 0x131316),
        Case("ink", LedgerColor.ink, 0xF4F2ED),
        Case("inkSecondary", LedgerColor.inkSecondary, 0xF4F2ED, 0.72),
        Case("inkMuted", LedgerColor.inkMuted, 0xF4F2ED, 0.48),
        Case("inkFaint", LedgerColor.inkFaint, 0xF4F2ED, 0.32),
        Case("inkDim", LedgerColor.inkDim, 0xF4F2ED, 0.28),
        Case("hairline", LedgerColor.hairline, 0xF4F2ED, 0.08),
        Case("hairlineStrong", LedgerColor.hairlineStrong, 0xF4F2ED, 0.14),
        Case("accent", LedgerColor.accent, 0xFF5B22),
        Case("accentText", LedgerColor.accentText, 0xFF5B22),
        Case("accentSoft", LedgerColor.accentSoft, 0xFF5B22, 0.16),
        Case("accentLine", LedgerColor.accentLine, 0xFF5B22, 0.4),
        Case("onAccent", LedgerColor.onAccent, 0xFFFFFF)
    ]

    nonisolated static let light: [Case] = [
        Case("ground", LedgerColor.ground, 0xEFEDE6),
        Case("surface", LedgerColor.surface, 0xFFFFFF),
        Case("ink", LedgerColor.ink, 0x16150F),
        Case("inkSecondary", LedgerColor.inkSecondary, 0x16150F, 0.72),
        Case("inkMuted", LedgerColor.inkMuted, 0x16150F, 0.60),
        Case("inkFaint", LedgerColor.inkFaint, 0x16150F, 0.32),
        Case("inkDim", LedgerColor.inkDim, 0x16150F, 0.28),
        Case("hairline", LedgerColor.hairline, 0x16150F, 0.08),
        Case("hairlineStrong", LedgerColor.hairlineStrong, 0x16150F, 0.14),
        Case("accent", LedgerColor.accent, 0xFF5B22),
        Case("accentText", LedgerColor.accentText, 0xB2390E),
        Case("accentSoft", LedgerColor.accentSoft, 0xFF5B22, 0.12),
        Case("accentLine", LedgerColor.accentLine, 0xFF5B22, 0.4),
        Case("onAccent", LedgerColor.onAccent, 0xFFFFFF)
    ]

    nonisolated static let watch: [Case] = [
        Case("watchGround", LedgerColor.watchGround, 0x000000),
        Case("watchInk", LedgerColor.watchInk, 0xFFFFFF),
        Case("watchInkSecondary", LedgerColor.watchInkSecondary, 0xFFFFFF, 0.55),
        Case("watchInkMuted", LedgerColor.watchInkMuted, 0xFFFFFF, 0.46),
        Case("watchOutline", LedgerColor.watchOutline, 0xFFFFFF, 0.22),
        Case("watchHairline", LedgerColor.watchHairline, 0xFFFFFF, 0.14),
        Case("watchTrack", LedgerColor.watchTrack, 0xFFFFFF, 0.13)
    ]

    @Test("Dark tokens resolve to the v2 palette", arguments: dark)
    func darkToken_resolved_matchesSpec(_ token: Case) {
        expect(token, resolvesIn: .dark)
    }

    #if os(iOS)
        @Test("Light tokens resolve to the v1 paper-and-ink palette", arguments: light)
        func lightToken_resolved_matchesSpec(_ token: Case) {
            expect(token, resolvesIn: .light)
        }
    #else
        @Test("watchOS has one appearance: a light environment still resolves the dark palette", arguments: dark)
        func token_lightEnvironmentOnWatch_staysDark(_ token: Case) {
            expect(token, resolvesIn: .light)
        }
    #endif

    @Test("Watch tokens resolve to the watch palette in either scheme", arguments: watch)
    func watchToken_resolved_matchesSpec(_ token: Case) {
        expect(token, resolvesIn: .dark)
        expect(token, resolvesIn: .light)
    }

    @Test("Spacing, radius and hairline tokens hold the brief's values")
    func geometryTokens_values_matchBrief() {
        let spacing = [LedgerSpacing.xs, LedgerSpacing.s, LedgerSpacing.m, LedgerSpacing.l, LedgerSpacing.xl]
        #expect(spacing == [4, 8, 12, 16, 24])
        #expect([LedgerSpacing.xxl, LedgerSpacing.screen] == [32, 26])
        #expect([LedgerRadius.pill, LedgerRadius.card, LedgerRadius.sheet, LedgerRadius.row] == [999, 26, 28, 16])
        #expect(LedgerHairline.width == 1)
    }

    private func expect(
        _ token: Case,
        resolvesIn scheme: ColorScheme,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = token.color.resolve(in: environment)
        let actual = [resolved.red, resolved.green, resolved.blue].map { Double($0) }
        let expected = [(token.hex >> 16) & 0xFF, (token.hex >> 8) & 0xFF, token.hex & 0xFF].map { Double($0) / 255 }
        let channelsMatch = zip(actual, expected).allSatisfy { abs($0 - $1) < 0.5 / 255 }
        #expect(channelsMatch, "\(token.name) \(scheme): \(actual) ≠ \(expected)", sourceLocation: sourceLocation)
        #expect(
            abs(Double(resolved.opacity) - token.alpha) < 0.002,
            "\(token.name) alpha",
            sourceLocation: sourceLocation
        )
    }
}
