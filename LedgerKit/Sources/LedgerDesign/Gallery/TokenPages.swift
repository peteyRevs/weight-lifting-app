#if DEBUG
    import SwiftUI

    // The DesignGallery's token pages: every token drawn with its name. Debug builds only (see
    // `DesignGallery`).

    /// Every colour token as a swatch with its name: the phone palette on the ground, so it follows
    /// the colour scheme and Increase Contrast, and the watch palette on black.
    struct ColorTokenPage: View {
        static let phone: [(name: String, color: Color)] = [
            ("ground", LedgerColor.ground), ("surface", LedgerColor.surface), ("ink", LedgerColor.ink),
            ("inkSecondary", LedgerColor.inkSecondary), ("inkMuted", LedgerColor.inkMuted),
            ("inkFaint", LedgerColor.inkFaint), ("inkDim", LedgerColor.inkDim), ("hairline", LedgerColor.hairline),
            ("hairlineStrong", LedgerColor.hairlineStrong), ("accent", LedgerColor.accent),
            ("accentText", LedgerColor.accentText), ("accentSoft", LedgerColor.accentSoft),
            ("accentLine", LedgerColor.accentLine), ("onAccent", LedgerColor.onAccent)
        ]

        static let watch: [(name: String, color: Color)] = [
            ("watchGround", LedgerColor.watchGround), ("watchInk", LedgerColor.watchInk),
            ("watchInkSecondary", LedgerColor.watchInkSecondary), ("watchInkMuted", LedgerColor.watchInkMuted),
            ("watchOutline", LedgerColor.watchOutline), ("watchHairline", LedgerColor.watchHairline),
            ("watchTrack", LedgerColor.watchTrack)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.l) {
                swatches(Self.phone, ink: LedgerColor.ink, rule: LedgerColor.hairlineStrong)
                swatches(Self.watch, ink: LedgerColor.watchInk, rule: LedgerColor.watchOutline).ledgerWatchPage()
            }
        }

        private func swatches(_ swatches: [(name: String, color: Color)], ink: Color, rule: Color) -> some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                ForEach(swatches, id: \.name) { swatch in
                    HStack(spacing: LedgerSpacing.m) {
                        Rectangle()
                            .fill(swatch.color)
                            .overlay(Rectangle().strokeBorder(rule, lineWidth: LedgerHairline.width))
                            .frame(width: LedgerSpacing.xxl, height: LedgerSpacing.xl)
                        Text(verbatim: swatch.name).ledgerFont(.caption).foregroundStyle(ink)
                    }
                }
            }
        }
    }

    /// Bold Text's weight step, then every type role: its name, then sample copy set in it.
    struct TypeTokenPage: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                Text(verbatim: "boldTextWeightStep · \(Int(LedgerFont.boldTextWeightStep))")
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                ForEach(LedgerFont.Role.allCases, id: \.self) { role in
                    VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                        Text(verbatim: role.rawValue).ledgerFont(.caption).foregroundStyle(LedgerColor.inkMuted)
                        Text(verbatim: role.spec.isTabular ? "185 × 5" : "Upper A — Push focus")
                            .ledgerFont(role)
                            .foregroundStyle(LedgerColor.ink)
                    }
                }
            }
        }
    }

    /// Every spacing step as a bar that long, with its name and points.
    struct SpacingTokenPage: View {
        static let steps: [(name: String, points: CGFloat)] = [
            ("xs", LedgerSpacing.xs), ("s", LedgerSpacing.s), ("m", LedgerSpacing.m), ("l", LedgerSpacing.l),
            ("xl", LedgerSpacing.xl), ("xxl", LedgerSpacing.xxl), ("screen", LedgerSpacing.screen)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                ForEach(Self.steps, id: \.name) { step in
                    HStack(spacing: LedgerSpacing.m) {
                        Rectangle().fill(LedgerColor.accentSoft).frame(width: step.points, height: LedgerSpacing.m)
                        Text(verbatim: "\(step.name) · \(Int(step.points))")
                            .ledgerFont(.caption)
                            .foregroundStyle(LedgerColor.ink)
                    }
                }
            }
        }
    }

    /// Every corner radius on an outlined box, with its name and points.
    struct RadiusTokenPage: View {
        static let radii: [(name: String, points: CGFloat)] = [
            ("row", LedgerRadius.row), ("card", LedgerRadius.card), ("sheet", LedgerRadius.sheet),
            ("pill", LedgerRadius.pill)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                ForEach(Self.radii, id: \.name) { radius in
                    HStack(spacing: LedgerSpacing.m) {
                        RoundedRectangle(cornerRadius: radius.points, style: .circular)
                            .strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
                            .frame(width: 3 * LedgerSpacing.xxl, height: 2 * LedgerSpacing.xxl)
                        Text(verbatim: "\(radius.name) · \(Int(radius.points))")
                            .ledgerFont(.caption)
                            .foregroundStyle(LedgerColor.ink)
                    }
                }
            }
        }
    }

    /// The rule weight, drawn in both rule colours.
    struct HairlineTokenPage: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(verbatim: "width · \(Int(LedgerHairline.width))")
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                HairlineRule()
                HairlineRule(LedgerColor.hairlineStrong)
            }
        }
    }

    /// The motion tokens: `snappy` and the buzz, played on demand (`snappy` moves a word, `buzz` shakes
    /// one, or pulses it under Reduce Motion), then the buzz's cycle and repeats.
    struct MotionTokenPage: View {
        @State private var plays = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                HStack(spacing: LedgerSpacing.l) {
                    PillButton("Play") {
                        withAnimation(reduceMotion ? nil : LedgerMotion.snappy) { plays += 1 }
                    }
                    Text(verbatim: "snappy")
                        .offset(x: plays.isMultiple(of: 2) ? 0 : LedgerSpacing.l)
                    Text(verbatim: "buzz")
                        .ledgerBuzz(trigger: plays)
                }
                Text(verbatim: "buzzCycle · \(LedgerMotion.buzzCycle) s")
                Text(verbatim: "buzzRepeats · \(LedgerMotion.buzzRepeats)")
            }
            .ledgerFont(.caption)
            .foregroundStyle(LedgerColor.ink)
        }
    }

    /// Every icon, with its name.
    struct IconTokenPage: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                ForEach(LedgerIcon.allCases, id: \.self) { icon in
                    HStack(spacing: LedgerSpacing.m) {
                        LedgerIconView(icon, sizedAs: .subheading).foregroundStyle(LedgerColor.ink)
                        Text(verbatim: "\(icon)").ledgerFont(.caption).foregroundStyle(LedgerColor.ink)
                    }
                }
            }
        }
    }
#endif
