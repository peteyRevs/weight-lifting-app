#if os(iOS)
    import LedgerDesign
    import SwiftUI
    import Testing

    /// A colour pair a slice-2 component draws, with the WCAG 2.x minimum it needs: 4.5:1 for text
    /// (every pair here also carries text under WCAG's large-text sizes, such as 10–12 pt labels),
    /// 3:1 for the bold button label (Pete, 2026-09-27) and 3:1 for non-text marks that identify a
    /// control or its state (1.4.11).
    nonisolated struct ComponentColorPair: Sendable, CustomTestStringConvertible {
        let name: String
        let foreground: Color
        let background: Color
        let minimum: Double

        var testDescription: String {
            name
        }

        static func onGrounds(_ name: String, _ foreground: Color, minimum: Double = 4.5) -> [Self] {
            [
                Self(
                    name: "\(name) on ground",
                    foreground: foreground,
                    background: LedgerColor.ground,
                    minimum: minimum
                ),
                Self(
                    name: "\(name) on surface",
                    foreground: foreground,
                    background: LedgerColor.surface,
                    minimum: minimum
                )
            ]
        }

        static let text: [Self] =
            [Self(
                name: "PillButton filled: ground on ink",
                foreground: LedgerColor.ground,
                background: LedgerColor.ink,
                minimum: 4.5
            )]
            + onGrounds("PillButton outline title: ink", LedgerColor.ink)
            + onGrounds("PillButton ghost title: inkMuted", LedgerColor.inkMuted)
            + onGrounds("Stepper step: inkMuted", LedgerColor.inkMuted)
            + onGrounds("SetRow active label: accentText", LedgerColor.accentText)
            + onGrounds("SetRow done numerals and pending label: inkMuted", LedgerColor.inkMuted)
            + onGrounds("SetRowHeader: inkMuted", LedgerColor.inkMuted)
            + onGrounds("HairlineRow detail: inkMuted", LedgerColor.inkMuted)
            + onGrounds("Eyebrow accent: accentText", LedgerColor.accentText)
            + onGrounds("RestRing label: ink", LedgerColor.ink)
            + [Self(
                name: "PrimaryButton title: onAccent on accent (bold)",
                foreground: LedgerColor.onAccent,
                background: LedgerColor.accent,
                minimum: 3
            )]

        /// Not asserted: the ring's `accent` arc on paper (2.65:1, 1.98:1 against its own track). The
        /// countdown in the ring carries the same information, so 1.4.11 does not require the arc
        /// (implementation notes, slice 2, decision 1).
        static let nonText: [Self] =
            onGrounds("SetRow check, pending ring: inkMuted", LedgerColor.inkMuted, minimum: 3)
                + onGrounds("SetRow check, active ring: accentText", LedgerColor.accentText, minimum: 3)
                + onGrounds("SetRow check, done disc: accent", LedgerColor.accent, minimum: 3)
                + [Self(
                    name: "SetRow check, done tick: onAccent on accent",
                    foreground: LedgerColor.onAccent,
                    background: LedgerColor.accent,
                    minimum: 3
                )]
                + onGrounds("IconPillButton and stepper glyphs: inkSecondary", LedgerColor.inkSecondary, minimum: 3)
    }

    /// Value-only: resolves tokens through SwiftUI's environment (colour scheme and Increase Contrast).
    @Suite("Component contrast (adversarial, slice 2 round 1)", .tags(.design))
    nonisolated struct ComponentContrastAdversarialTests {
        static func resolve(_ color: Color, _ scheme: ColorScheme, increased: Bool) -> SRGB {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            environment._colorSchemeContrast = increased ? .increased : .standard
            return SRGB(color.resolve(in: environment))
        }

        static func ratios(_ pair: ComponentColorPair) -> [(setting: String, ratio: Double)] {
            [ColorScheme.light, .dark].flatMap { scheme in
                [false, true].map { increased in
                    let background = resolve(pair.background, scheme, increased: increased)
                    let ratio = resolve(pair.foreground, scheme, increased: increased).contrast(on: background)
                    return ("\(scheme == .dark ? "dark" : "light")\(increased ? ", Increase Contrast" : "")", ratio)
                }
            }
        }

        @Test("The resolver sees Increase Contrast (inkMuted steps up to .74)")
        func resolver_increasedContrast_isApplied() {
            #expect(abs(Self.resolve(LedgerColor.inkMuted, .dark, increased: true).alpha - 0.74) < 0.002)
            #expect(abs(Self.resolve(LedgerColor.inkMuted, .dark, increased: false).alpha - 0.51) < 0.002)
        }

        @Test(
            "Slice-2 text meets AA in both schemes, with and without Increase Contrast",
            arguments: ComponentColorPair.text
        )
        func text_meetsAA(pair: ComponentColorPair) {
            for (setting, ratio) in Self.ratios(pair) {
                #expect(ratio >= pair.minimum, "\(pair.name), \(setting): \(String(format: "%.2f", ratio)):1")
            }
        }

        @Test(
            "Slice-2 control marks meet WCAG 1.4.11's 3:1 in both schemes, with and without Increase Contrast",
            arguments: ComponentColorPair.nonText
        )
        func nonText_meetsThreeToOne(pair: ComponentColorPair) {
            for (setting, ratio) in Self.ratios(pair) {
                #expect(ratio >= pair.minimum, "\(pair.name), \(setting): \(String(format: "%.2f", ratio)):1")
            }
        }
    }
#endif
