import LedgerDesign
import Testing

/// Spacing, radius and hairline scales against the brief's public surface and spec §8.6.
@Suite("Layout tokens (adversarial)", .tags(.design))
nonisolated struct LayoutTokenAdversarialTests {
    @Test("Spacing is the brief's 4/8/12/16/24/32 scale plus the 26 pt v2 screen inset.")
    func spacing_values_matchBrief() {
        let scale = [
            LedgerSpacing.xs, LedgerSpacing.s, LedgerSpacing.m, LedgerSpacing.l, LedgerSpacing.xl, LedgerSpacing.xxl
        ]
        #expect(scale == [4, 8, 12, 16, 24, 32])
        // v2 Today / Library / History: `padding: 72px 26px` (§8.6 "sides 20–26 px").
        #expect(LedgerSpacing.screen == 26)
    }

    @Test("Every spacing step is on the 4 pt grid and strictly larger than the one before.")
    func spacing_scale_isStrictlyIncreasingOnFourPointGrid() {
        let scale = [
            LedgerSpacing.xs, LedgerSpacing.s, LedgerSpacing.m, LedgerSpacing.l, LedgerSpacing.xl, LedgerSpacing.xxl
        ]
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
        #expect(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }

    @Test("Radii: pill 999, card 26 (v2 rest card), sheet 28 (v2 swap sheet), row 16 (§8.6).")
    func radius_values_matchSpec() {
        #expect(LedgerRadius.pill == 999)
        #expect(LedgerRadius.card == 26)
        #expect(LedgerRadius.sheet == 28)
        #expect(LedgerRadius.row == 16)
    }

    @Test("A pill fully rounds the tallest control the brief lists, even at AX5 (half height < 999).")
    func radius_pill_roundsAnyControl() {
        // Primary CTA ≈ 54 pt (19 pt padding × 2 + 16 pt label); at AX5 the label is ~3.3× → ~91 pt.
        let tallestCTA: Double = 19 * 2 + 16 * 3.3
        #expect(LedgerRadius.pill >= tallestCTA / 2)
    }

    @Test("Hairlines are 1 pt, the v2 rule and border weight (§8.6).")
    func hairline_width_isOnePoint() {
        #expect(LedgerHairline.width == 1)
    }
}
