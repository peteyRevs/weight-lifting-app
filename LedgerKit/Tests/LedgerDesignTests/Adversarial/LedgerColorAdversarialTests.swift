import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing
#if os(iOS)
    import UIKit
#endif

/// The phone tokens with their spec values. Light is v1 "paper / ink" (§8.1), dark is v2
/// (§8.2); decision #1 ships both. Alphas are the brief's (.72/.45/.32/.08/.14) plus `DIM` .28.
nonisolated enum PhoneToken: String, CaseIterable, Sendable {
    case ground, surface, ink, inkSecondary, inkMuted, inkFaint, inkDim, hairline, hairlineStrong
    case accent, accentText, accentSoft, accentLine, onAccent

    static let paper: UInt32 = 0xEFEDE6, card: UInt32 = 0xFFFFFF, inkHex: UInt32 = 0x16150F
    static let groundHex: UInt32 = 0x0B0B0D, sheet: UInt32 = 0x131316, text: UInt32 = 0xF4F2ED
    /// F06 fix round (Pete, WCAG AA): accentDeep #C63F0F → #C03D0F, inkMuted .45 → .48 dark / .60 light.
    /// F06 fix round 2 (same decision, finding 14): accentDeep → #B2390E, for 4.5:1 on accentSoft.
    /// F06 fix round 3 (same decision, finding 20): inkMuted → .51 dark / .62 light, for 4.5:1 on accentSoft.
    static let orange: UInt32 = 0xFF5B22, orangeDeep: UInt32 = 0xB2390E

    var color: Color {
        switch self {
        case .ground: LedgerColor.ground
        case .surface: LedgerColor.surface
        case .ink: LedgerColor.ink
        case .inkSecondary: LedgerColor.inkSecondary
        case .inkMuted: LedgerColor.inkMuted
        case .inkFaint: LedgerColor.inkFaint
        case .inkDim: LedgerColor.inkDim
        case .hairline: LedgerColor.hairline
        case .hairlineStrong: LedgerColor.hairlineStrong
        case .accent: LedgerColor.accent
        case .accentText: LedgerColor.accentText
        case .accentSoft: LedgerColor.accentSoft
        case .accentLine: LedgerColor.accentLine
        case .onAccent: LedgerColor.onAccent
        }
    }

    /// Ink at a fixed alpha, or nil for tokens that are not ink.
    private func inkAlpha(light: Bool) -> Double? {
        switch self {
        case .ink: 1
        case .inkSecondary: 0.72
        case .inkMuted: light ? 0.62 : 0.51
        case .inkFaint: 0.32
        case .inkDim: 0.28 // v2 `DIM`
        case .hairline: 0.08 // v2 `LINE`, v1 list rows
        case .hairlineStrong: 0.14
        default: nil
        }
    }

    /// Light value; nil where the light prototype has no counterpart.
    var light: SRGB? {
        if let alpha = inkAlpha(light: true) {
            return SRGB(Self.inkHex, alpha: alpha)
        }
        return switch self {
        case .ground: SRGB(Self.paper)
        case .surface: SRGB(Self.card)
        case .accent: SRGB(Self.orange)
        case .accentText: SRGB(Self.orangeDeep) // §8.1 "orange text on light backgrounds"
        case .accentSoft: SRGB(Self.orange, alpha: 0.12) // §8.1 accentTint
        case .onAccent: SRGB(0xFFFFFF) // v1 CTAs: background #FF5B22; color #fff
        default: nil // accentLine is v2-only
        }
    }

    var dark: SRGB {
        if let alpha = inkAlpha(light: false) {
            return SRGB(Self.text, alpha: alpha)
        }
        return switch self {
        case .ground: SRGB(Self.groundHex)
        case .surface: SRGB(Self.sheet)
        case .accent, .accentText: SRGB(Self.orange)
        case .accentSoft: SRGB(Self.orange, alpha: 0.16) // brief: accent .16
        case .accentLine: SRGB(Self.orange, alpha: 0.4) // §8.2 active set row rule
        default: SRGB(0xFFFFFF) // onAccent: v2 CTA and done-check `#fff` on orange
        }
    }
}

/// Watch tokens (§8.3): one appearance, white alphas on `#000`.
nonisolated enum WatchToken: String, CaseIterable, Sendable {
    case watchGround, watchInk, watchInkSecondary, watchInkMuted, watchOutline, watchHairline, watchTrack

    var color: Color {
        switch self {
        case .watchGround: LedgerColor.watchGround
        case .watchInk: LedgerColor.watchInk
        case .watchInkSecondary: LedgerColor.watchInkSecondary
        case .watchInkMuted: LedgerColor.watchInkMuted
        case .watchOutline: LedgerColor.watchOutline
        case .watchHairline: LedgerColor.watchHairline
        case .watchTrack: LedgerColor.watchTrack
        }
    }

    var expected: SRGB {
        switch self {
        case .watchGround: SRGB(0x000000)
        case .watchInk: SRGB(0xFFFFFF)
        case .watchInkSecondary: SRGB(0xFFFFFF, alpha: 0.55)
        case .watchInkMuted: SRGB(0xFFFFFF, alpha: 0.46) // F06 fix round (WCAG AA): .4 → .46
        case .watchOutline: SRGB(0xFFFFFF, alpha: 0.22)
        case .watchHairline: SRGB(0xFFFFFF, alpha: 0.14)
        case .watchTrack: SRGB(0xFFFFFF, alpha: 0.13)
        }
    }
}

extension RenderingSuites {
    @Suite("LedgerColor (adversarial)", .tags(.design))
    struct LedgerColorAdversarialTests {
        #if os(iOS)
            @Test(
                "Every phone token resolves to its spec hex and alpha in light and dark (criterion 2).",
                arguments: PhoneToken.allCases
            )
            func phoneToken_bothSchemes_matchesSpec(token: PhoneToken) {
                let dark = Resolve.color(token.color, in: .dark)
                #expect(dark.matches(token.dark), "\(token) dark: \(dark), spec \(token.dark)")
                if let light = token.light {
                    let resolved = Resolve.color(token.color, in: .light)
                    #expect(resolved.matches(light), "\(token) light: \(resolved), spec \(light)")
                }
            }

            @Test(
                "Resolved UIColor components equal the spec in both trait styles (criterion 2, literal).",
                arguments: PhoneToken.allCases
            )
            func phoneToken_uiColor_matchesSpec(token: PhoneToken) {
                let styles: [(UIUserInterfaceStyle, SRGB?)] = [(.dark, token.dark), (.light, token.light)]
                for (style, expected) in styles {
                    guard let expected else { continue }
                    let color = UIColor(token.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    var alpha: CGFloat = 0
                    #expect(
                        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
                        "\(token) is not RGB-convertible"
                    )
                    let actual = SRGB(red: red, green: green, blue: blue, alpha: alpha)
                    #expect(actual.matches(expected), "\(token) \(style.rawValue): \(actual), spec \(expected)")
                }
            }

            @Test(
                "Opaque tokens paint their spec pixel in each scheme through the snapshot renderer.",
                arguments: [PhoneToken.ground, .surface, .ink, .accent, .accentText, .onAccent]
            )
            func phoneToken_rendered_paintsSpecPixel(token: PhoneToken) throws {
                for scheme in [ColorScheme.light, .dark] {
                    let expected = try #require(scheme == .dark ? token.dark : token.light)
                    let image = try #require(RenderedImage.render(
                        token.color.frame(width: 4, height: 4),
                        colorScheme: scheme
                    ))
                    let pixel = try #require(PixelBuffer(image)).pixel(column: 2, row: 2)
                    let actual = SRGB(
                        red: Double(pixel.red) / 255, green: Double(pixel.green) / 255,
                        blue: Double(pixel.blue) / 255, alpha: Double(pixel.alpha) / 255
                    )
                    #expect(actual.matches(expected), "\(token) \(scheme): painted \(actual), spec \(expected)")
                }
            }
        #endif

        #if os(watchOS)
            @Test(
                "On watchOS phone tokens take their dark values in either scheme (one appearance, §8.3).",
                arguments: PhoneToken.allCases
            )
            func phoneToken_watchOS_isAlwaysDark(token: PhoneToken) {
                for scheme in [ColorScheme.dark, .light] {
                    let resolved = Resolve.color(token.color, in: scheme)
                    #expect(resolved.matches(token.dark), "\(token) in \(scheme): \(resolved), spec \(token.dark)")
                }
            }
        #endif

        @Test(
            "Watch tokens are #000 / white alphas from §8.3 and ignore the colour scheme.",
            arguments: WatchToken.allCases
        )
        func watchToken_anyScheme_matchesSpec(token: WatchToken) {
            for scheme in [ColorScheme.dark, .light] {
                let resolved = Resolve.color(token.color, in: scheme)
                #expect(resolved.matches(token.expected), "\(token) in \(scheme): \(resolved), spec \(token.expected)")
            }
        }

        @Test("Muted dark ink composites over the ground exactly as the prototype's rgba text does.")
        func inkMuted_renderedOverGround_matchesBrowserComposite() throws {
            // v2 `rgba(244,242,237,.45)` on `#0B0B0D`, blended in gamma sRGB as a browser does
            // (F06 fix round: .48 for WCAG AA; fix round 3: .51, AA on accentSoft too).
            let expected = SRGB(PhoneToken.text, alpha: 0.51).composited(over: SRGB(PhoneToken.groundHex))
            let swatch = LedgerColor.inkMuted.frame(width: 4, height: 4).background(LedgerColor.ground)
            let image = try #require(RenderedImage.render(swatch, colorScheme: .dark))
            let pixel = try #require(PixelBuffer(image)).pixel(column: 2, row: 2)
            let actual = SRGB(
                red: Double(pixel.red) / 255, green: Double(pixel.green) / 255, blue: Double(pixel.blue) / 255, alpha: 1
            )
            #expect(abs(actual.red - expected.red) <= 2.0 / 255, "painted \(actual), browser \(expected)")
            #expect(abs(actual.blue - expected.blue) <= 2.0 / 255, "painted \(actual), browser \(expected)")
        }
    }
}
