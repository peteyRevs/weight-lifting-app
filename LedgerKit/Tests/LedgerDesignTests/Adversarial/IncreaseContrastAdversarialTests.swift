#if os(iOS)
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// Round 2: the AA palette and the iOS Increase Contrast ladder (Pete, 2026-09-27). The
        /// ladder's promise is `LedgerColor`'s own doc comment: "text to 7:1, `inkFaint` to 4.5:1".
        /// Checked through UIKit traits and through SwiftUI's environment, which is what a view gets.
        @Suite("Increase Contrast (adversarial, round 2)", .tags(.design))
        struct IncreaseContrastAdversarialTests {
            static let inkLadder: [PhoneToken] = [
                .ink, .inkSecondary, .inkMuted, .inkFaint, .inkDim, .hairlineStrong, .hairline
            ]

            static func resolve(_ color: Color, _ scheme: ColorScheme, increased: Bool) throws -> SRGB {
                let traits = UITraitCollection { traits in
                    traits.userInterfaceStyle = scheme == .dark ? .dark : .light
                    traits.accessibilityContrast = increased ? .high : .normal
                }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                let resolved = UIColor(color).resolvedColor(with: traits)
                try #require(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                return SRGB(red: red, green: green, blue: blue, alpha: alpha)
            }

            static func ratio(
                _ token: PhoneToken,
                on ground: PhoneToken,
                _ scheme: ColorScheme,
                increased: Bool
            ) throws -> Double {
                let background = try resolve(ground.color, scheme, increased: increased)
                return try resolve(token.color, scheme, increased: increased).contrast(on: background)
            }

            /// `token` painted over `ground` by SwiftUI, with Increase Contrast set in the environment.
            static func rendered(
                _ token: PhoneToken,
                _ scheme: ColorScheme,
                contrast: ColorSchemeContrast
            ) throws -> SRGB {
                let swatch = token.color.frame(width: 4, height: 4).background(LedgerColor.ground)
                    .environment(\._colorSchemeContrast, contrast)
                let image = try #require(Probe.image(swatch, colorScheme: scheme))
                let pixel = try #require(PixelBuffer(image)).pixel(column: 2, row: 2)
                return SRGB(
                    red: Double(pixel.red) / 255,
                    green: Double(pixel.green) / 255,
                    blue: Double(pixel.blue) / 255,
                    alpha: 1
                )
            }

            @Test(
                "With Increase Contrast, text reaches 7:1 and inkFaint 4.5:1 on ground and surface, light and dark.",
                arguments: [ColorScheme.light, .dark]
            )
            func increasedContrast_inkLadder_meetsItsPromise(scheme: ColorScheme) throws {
                let promises: [(PhoneToken, Double)] = [(.ink, 7), (.inkSecondary, 7), (.inkMuted, 7), (.inkFaint, 4.5)]
                for (token, minimum) in promises {
                    for ground in [PhoneToken.ground, .surface] {
                        let ratio = try Self.ratio(token, on: ground, scheme, increased: true)
                        #expect(
                            ratio >= minimum,
                            "\(token) on \(ground), \(scheme): \(String(format: "%.2f", ratio)):1"
                        )
                    }
                }
            }

            @Test(
                "Increase Contrast never lowers a token's contrast, and keeps the ladder's order.",
                arguments: [ColorScheme.light, .dark]
            )
            func increasedContrast_everyToken_neverWorse(scheme: ColorScheme) throws {
                var increased: [Double] = []
                for token in Self.inkLadder + [.accentText] {
                    let normal = try Self.ratio(token, on: .ground, scheme, increased: false)
                    let high = try Self.ratio(token, on: .ground, scheme, increased: true)
                    #expect(high >= normal - 0.001, "\(token) \(scheme): \(normal) → \(high)")
                    if token != .accentText {
                        increased.append(high)
                    }
                }
                #expect(zip(increased, increased.dropFirst()).allSatisfy { $0 > $1 }, "ladder order: \(increased)")
            }

            @Test(
                "Increase Contrast leaves grounds, surfaces, accent and onAccent alone, and ink stays ink.",
                arguments: [PhoneToken.ground, .surface, .accent, .onAccent, .ink]
            )
            func increasedContrast_fixedTokens_unchanged(token: PhoneToken) throws {
                for scheme in [ColorScheme.light, .dark] {
                    let normal = try Self.resolve(token.color, scheme, increased: false)
                    let high = try Self.resolve(token.color, scheme, increased: true)
                    #expect(high.matches(normal), "\(token) \(scheme): \(normal) → \(high)")
                }
            }

            @Test(
                "SwiftUI's environment reaches the ladder: Color.resolve at increased contrast matches UIKit.",
                arguments: [ColorScheme.light, .dark]
            )
            func increasedContrast_swiftUIResolve_matchesTraitResolution(scheme: ColorScheme) throws {
                for token in Self.inkLadder {
                    var environment = EnvironmentValues()
                    environment.colorScheme = scheme
                    environment._colorSchemeContrast = .increased
                    let swiftUI = SRGB(token.color.resolve(in: environment))
                    let uiKit = try Self.resolve(token.color, scheme, increased: true)
                    #expect(swiftUI.matches(uiKit), "\(token) \(scheme): SwiftUI \(swiftUI), UIKit \(uiKit)")
                }
            }

            @Test(
                "A SwiftUI view paints the stronger ink when the environment asks for increased contrast.",
                arguments: [ColorScheme.light, .dark]
            )
            func increasedContrast_renderedView_paintsTheLadder(scheme: ColorScheme) throws {
                let step = 1.5 / 255
                for token in [PhoneToken.inkSecondary, .inkMuted, .inkFaint] {
                    let ground = try Self.resolve(LedgerColor.ground, scheme, increased: true)
                    let expected = try Self.resolve(token.color, scheme, increased: true).composited(over: ground)
                    let normal = try Self.rendered(token, scheme, contrast: .standard)
                    let high = try Self.rendered(token, scheme, contrast: .increased)
                    let close = abs(high.red - expected.red) <= step && abs(high.green - expected.green) <= step
                        && abs(high.blue - expected.blue) <= step
                    #expect(close, "\(token) \(scheme): painted \(high), expected \(expected)")
                    #expect(
                        high.contrast(on: ground) > normal.contrast(on: ground) + 0.5,
                        "\(token) \(scheme): \(normal) → \(high)"
                    )
                }
            }

            @Test(
                "Orange chip text on its orange tint (§8.1: accentDeep text on accentTint) meets AA, light and dark.",
                arguments: [ColorScheme.light, .dark]
            )
            func accentText_onAccentSoft_meetsAA(scheme: ColorScheme) throws {
                // v1 program builder: the active "Deload" button and equipment chips are `600 11.5px`
                // `#C63F0F` on `rgba(255,91,34,.12)`, so the 4.5:1 minimum applies.
                for ground in [PhoneToken.ground, .surface] {
                    for increased in [false, true] {
                        let base = try Self.resolve(ground.color, scheme, increased: increased)
                        let tint = try Self.resolve(LedgerColor.accentSoft, scheme, increased: increased)
                            .composited(over: base)
                        let text = try Self.resolve(LedgerColor.accentText, scheme, increased: increased)
                        let ratio = text.contrast(on: tint)
                        let label = "\(scheme) on \(ground)\(increased ? " (Increase Contrast)" : "")"
                        #expect(ratio >= 4.5, "accentText on accentSoft, \(label): \(String(format: "%.2f", ratio)):1")
                    }
                }
            }
        }
    }
#endif
