import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Round 3's painted-swatch helper.
private typealias Chip = RenderingSuites.AccentChipContrastAdversarialTests

extension RenderingSuites {
    /// Round 4 (close-out of finding 20): fix round 3 raised `inkMuted` to .51 dark / .62 light so it
    /// keeps 4.5:1 on the `accentSoft` tint. Checked as SwiftUI paints it on every ground and tint the
    /// token can sit on — ground and surface, bare and under the tint, both schemes, with and without
    /// Increase Contrast (iOS) — and on the watch's black ground, where phone tokens resolve dark.
    @Suite("Muted text contrast (adversarial, round 4)", .tags(.design))
    struct MutedTextContrastAdversarialTests {
        /// Contrast of `text` painted over `layers`, against `layers` alone.
        static func ratio(
            _ text: Color,
            over layers: [Color],
            _ scheme: ColorScheme,
            increased: Bool
        ) throws -> Double {
            let background = try Chip.painted(layers, scheme, increased: increased)
            let glyph = try Chip.painted(layers + [text], scheme, increased: increased)
            return glyph.contrast(on: background)
        }

        @Test(
            "inkMuted is at least 4.5:1 as painted on ground and surface, bare and under accentSoft.",
            arguments: ChipGround.all
        )
        func inkMuted_everyGroundAndTint_meetsAA(chip: ChipGround) throws {
            let ground = chip.onSurface ? LedgerColor.surface : LedgerColor.ground
            for layers in [[ground], [ground, LedgerColor.accentSoft]] {
                let ratio = try Self.ratio(LedgerColor.inkMuted, over: layers, chip.scheme, increased: chip.increased)
                #expect(
                    ratio >= 4.5,
                    """
                    inkMuted on \(layers.count == 2 ? "accentSoft over " : "")\(chip.testDescription): \
                    \(String(format: "%.3f", ratio)):1
                    """
                )
            }
        }

        @Test("Phone inkMuted is at least 4.5:1 on watchGround, bare and under accentSoft (it resolves dark there).")
        func inkMuted_onWatchGround_meetsAA() throws {
            for layers in [[LedgerColor.watchGround], [LedgerColor.watchGround, LedgerColor.accentSoft]] {
                let ratio = try Self.ratio(LedgerColor.inkMuted, over: layers, .dark, increased: false)
                #expect(
                    ratio >= 4.5,
                    "inkMuted on \(layers.count == 2 ? "accentSoft over " : "")watchGround: \(ratio):1"
                )
            }
        }
    }
}
