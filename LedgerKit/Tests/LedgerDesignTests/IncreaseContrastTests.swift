@testable import LedgerDesign
import SwiftUI
import Testing
#if os(iOS)
    import UIKit
#endif

/// Pete's contrast decision (2026-09-27): the ink ladder steps up under iOS Increase Contrast.
/// Text reaches WCAG AAA (7:1) and `inkFaint` AA (4.5:1) on both grounds; hairlines get stronger;
/// the accent family is unchanged. watchOS has no dynamic colours, so this is iOS only.
@Suite("IncreaseContrast", .tags(.design))
struct IncreaseContrastTests {
    #if os(iOS)
        nonisolated struct Step: Sendable, CustomTestStringConvertible {
            let name: String
            let color: Color
            let alpha: Double
            let minimumRatio: Double
            var testDescription: String {
                name
            }
        }

        nonisolated static let steps: [Step] = [
            Step(name: "inkSecondary", color: LedgerColor.inkSecondary, alpha: 0.86, minimumRatio: 7),
            Step(name: "inkMuted", color: LedgerColor.inkMuted, alpha: 0.74, minimumRatio: 7),
            Step(name: "inkFaint", color: LedgerColor.inkFaint, alpha: 0.60, minimumRatio: 4.5),
            Step(name: "inkDim", color: LedgerColor.inkDim, alpha: 0.50, minimumRatio: 3),
            Step(name: "hairline", color: LedgerColor.hairline, alpha: 0.20, minimumRatio: 1.5),
            Step(name: "hairlineStrong", color: LedgerColor.hairlineStrong, alpha: 0.30, minimumRatio: 1.9)
        ]

        static func resolve(_ color: Color, _ style: UIUserInterfaceStyle, high: Bool) -> SRGB {
            let traits = UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.accessibilityContrast = high ? .high : .normal
            }
            var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SRGB(red: red, green: green, blue: blue, alpha: alpha)
        }

        @Test("Each ink step is stronger with Increase Contrast and meets its ratio on both grounds", arguments: steps)
        func inkStep_increasedContrast_meetsRatio(_ step: Step) {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let increased = Self.resolve(step.color, style, high: true)
                let normal = Self.resolve(step.color, style, high: false)
                #expect(abs(increased.alpha - step.alpha) < 0.002, "\(step.name) \(style.rawValue): \(increased)")
                #expect(increased.alpha > normal.alpha)
                for ground in [LedgerColor.ground, LedgerColor.surface] {
                    let ratio = increased.contrast(on: Self.resolve(ground, style, high: true))
                    #expect(ratio >= step.minimumRatio, "\(step.name) \(style.rawValue): \(ratio):1")
                }
            }
        }

        @Test("Grounds, full ink and the accent family do not change with Increase Contrast")
        func fixedTokens_increasedContrast_areUnchanged() {
            let fixed = [
                LedgerColor.ground, LedgerColor.surface, LedgerColor.ink, LedgerColor.accent,
                LedgerColor.accentText, LedgerColor.accentSoft, LedgerColor.accentLine, LedgerColor.onAccent
            ]
            for color in fixed {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    #expect(Self.resolve(color, style, high: true) == Self.resolve(color, style, high: false))
                }
            }
        }
    #endif
}
