import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// One chip background: the scheme, the ground under the tint, and Increase Contrast.
nonisolated struct ChipGround: Sendable, CustomTestStringConvertible {
    let scheme: ColorScheme
    let onSurface: Bool
    let increased: Bool

    var testDescription: String {
        "\(scheme) on \(onSurface ? "surface" : "ground")\(increased ? ", Increase Contrast" : "")"
    }

    /// Light and dark, over ground and surface; with and without Increase Contrast where SwiftUI
    /// exposes it (iOS).
    static let all: [Self] = [ColorScheme.light, .dark].flatMap { scheme in
        [false, true].flatMap { onSurface in
            increasedOptions.map { Self(scheme: scheme, onSurface: onSurface, increased: $0) }
        }
    }

    /// Without Increase Contrast only.
    static let standard = all.filter { !$0.increased }

    static var increasedOptions: [Bool] {
        #if os(iOS)
            [false, true]
        #else
            [false]
        #endif
    }
}

extension RenderingSuites {
    /// Round 3: finding 14's fix (`accentText` light `#B2390E`), checked the way a chip is drawn —
    /// SwiftUI paints `accentSoft` over the ground, the text over that, and the ratio is taken from the
    /// painted pixels, so 8-bit compositing and the environment's contrast setting are included. Also
    /// the watch's current exercise row (LedgerWatch prototype: `rgba(255,91,34,.16)` on `#000` behind
    /// an orange row number, a white name and a `.4` white scheme line) and the other text tokens on
    /// the tint, which `accentSoft`'s doc comment offers as the fill "behind a selected item".
    @Suite("Accent chip contrast (adversarial, round 3)", .tags(.design))
    struct AccentChipContrastAdversarialTests {
        /// What SwiftUI paints for `layers` stacked bottom to top, read back from a 4×4 swatch.
        static func painted(_ layers: [Color], _ scheme: ColorScheme, increased: Bool) throws -> SRGB {
            let swatch = ZStack {
                ForEach(layers.indices, id: \.self) { layers[$0] }
            }
            .frame(width: 4, height: 4)
            #if os(iOS)
                let view = swatch.environment(\._colorSchemeContrast, increased ? .increased : .standard)
            #else
                let view = swatch
            #endif
            let image = try #require(Probe.image(view, colorScheme: scheme))
            let pixel = try #require(PixelBuffer(image)).pixel(column: 2, row: 2)
            return SRGB(
                red: Double(pixel.red) / 255,
                green: Double(pixel.green) / 255,
                blue: Double(pixel.blue) / 255,
                alpha: 1
            )
        }

        /// Contrast of `text` painted on `accentSoft` painted on `ground`.
        static func ratio(
            _ text: Color,
            onTintOver ground: Color,
            _ scheme: ColorScheme,
            increased: Bool
        ) throws -> Double {
            let tint = try painted([ground, LedgerColor.accentSoft], scheme, increased: increased)
            let glyph = try painted([ground, LedgerColor.accentSoft, text], scheme, increased: increased)
            return glyph.contrast(on: tint)
        }

        @Test(
            "Orange chip text on its tint (§8.1 accentDeep on accentTint, 600 11.5 px) is at least 4.5:1 as painted.",
            arguments: ChipGround.all
        )
        func accentText_onPaintedAccentSoft_meetsAA(chip: ChipGround) throws {
            let ground = chip.onSurface ? LedgerColor.surface : LedgerColor.ground
            let ratio = try Self.ratio(
                LedgerColor.accentText,
                onTintOver: ground,
                chip.scheme,
                increased: chip.increased
            )
            #expect(
                ratio >= 4.5,
                "accentText on accentSoft, \(chip.testDescription): \(String(format: "%.3f", ratio)):1"
            )
        }

        @Test(
            "The watch's current exercise row: orange number, white name and muted scheme line are 4.5:1 on the tint.",
            arguments: ["accent", "watchInk", "watchInkMuted"]
        )
        func watchCurrentRow_textOnTint_meetsAA(token: String) throws {
            let text = switch token {
            case "accent": LedgerColor.accent
            case "watchInk": LedgerColor.watchInk
            default: LedgerColor.watchInkMuted
            }
            let ratio = try Self.ratio(text, onTintOver: LedgerColor.watchGround, .dark, increased: false)
            #expect(ratio >= 4.5, "\(token) on accentSoft over watchGround: \(String(format: "%.3f", ratio)):1")
        }

        @Test(
            "Secondary and muted text on the selected-item tint are 4.5:1, as on the plain ground (brief NFR).",
            arguments: ChipGround.standard
        )
        func inkText_onSelectedItemTint_meetsAA(chip: ChipGround) throws {
            let ground = chip.onSurface ? LedgerColor.surface : LedgerColor.ground
            for (name, text) in [("inkSecondary", LedgerColor.inkSecondary), ("inkMuted", LedgerColor.inkMuted)] {
                let ratio = try Self.ratio(text, onTintOver: ground, chip.scheme, increased: false)
                #expect(
                    ratio >= 4.5,
                    "\(name) on accentSoft, \(chip.testDescription): \(String(format: "%.3f", ratio)):1"
                )
            }
        }
    }
}
