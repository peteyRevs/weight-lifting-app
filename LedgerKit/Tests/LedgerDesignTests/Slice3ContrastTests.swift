#if os(iOS)
    import LedgerDesign
    import SwiftUI
    import Testing

    /// Pete's rule for slice 3 (WCAG AA with the look kept): every pair of colours the new components
    /// draw, in both schemes, with and without Increase Contrast, resolved through SwiftUI as slice 2's
    /// `ComponentContrastAdversarialTests` resolves them. Text needs 4.5:1; the bold white label on the
    /// orange pill 3:1 (Pete's decision 7); a mark that alone carries a state 3:1 (WCAG 1.4.11). The
    /// watch has one, dark, appearance, so its pairs are the same in every setting.
    @Suite("Slice3Contrast", .tags(.design))
    nonisolated struct Slice3ContrastTests {
        static let text: [ComponentColorPair] =
            ComponentColorPair.onGrounds("WeekStrip weekday, planned and rest dates: inkMuted", LedgerColor.inkMuted)
                + ComponentColorPair.onGrounds("WeekStrip done date, StatTile value: ink", LedgerColor.ink)
                + ComponentColorPair.onGrounds("WeekStrip today, StatTile delta: accentText", LedgerColor.accentText)
                + ComponentColorPair.onGrounds("StatTile unit and caption: inkMuted", LedgerColor.inkMuted)
                + [
                    ComponentColorPair(
                        name: "SheetChrome title: ink on surface", foreground: LedgerColor.ink,
                        background: LedgerColor.surface, minimum: 4.5
                    ),
                    ComponentColorPair(
                        name: "SheetChrome cancel and body: inkMuted on surface", foreground: LedgerColor.inkMuted,
                        background: LedgerColor.surface, minimum: 4.5
                    )
                ]
                + ComponentColorPair.onGrounds("EmptyState body: inkMuted", LedgerColor.inkMuted)
                + [
                    watch(
                        "WatchPrimaryButton title: watchInk on accent (bold)", LedgerColor.watchInk,
                        on: LedgerColor.accent, minimum: 3
                    ),
                    watch("WatchRestRing label, WatchStatBlock value: watchInk", LedgerColor.watchInk),
                    watch("WatchStatBlock caption: watchInkMuted", LedgerColor.watchInkMuted),
                    watch("WatchStatBlock highlighted value: accent", LedgerColor.accent)
                ]

        /// Not asserted, like the rest ring's track and arc on paper (slice 2, decision 1): the
        /// progress bar's upcoming track (`hairlineStrong`) and the watch ring's track (`watchTrack`).
        /// Each is the unfilled remainder of a progress mark whose state is in words beside it or in
        /// its middle.
        static let nonText: [ComponentColorPair] =
            ComponentColorPair.onGrounds("WeekStrip done dot, planned ring: inkMuted", LedgerColor.inkMuted, minimum: 3)
                + ComponentColorPair.onGrounds("WeekStrip today dot: accentText", LedgerColor.accentText, minimum: 3)
                + ComponentColorPair.onGrounds("ProgressSegments done: inkMuted", LedgerColor.inkMuted, minimum: 3)
                + ComponentColorPair.onGrounds(
                    "ProgressSegments current: accentText",
                    LedgerColor.accentText,
                    minimum: 3
                )
                + [
                    watch("WatchRestRing arc: accent", LedgerColor.accent, minimum: 3),
                    watch("WatchPrimaryButton pill: accent", LedgerColor.accent, minimum: 3)
                ]

        static func watch(
            _ name: String,
            _ foreground: Color,
            on background: Color = LedgerColor.watchGround,
            minimum: Double = 4.5
        ) -> ComponentColorPair {
            ComponentColorPair(name: name, foreground: foreground, background: background, minimum: minimum)
        }

        @Test("Slice 3's text meets AA in both schemes, with and without Increase Contrast", arguments: text)
        func text_meetsAA(pair: ComponentColorPair) {
            for (setting, ratio) in ComponentContrastAdversarialTests.ratios(pair) {
                #expect(ratio >= pair.minimum, "\(pair.name), \(setting): \(String(format: "%.2f", ratio)):1")
            }
        }

        @Test(
            "Slice 3's state marks meet WCAG 1.4.11's 3:1 in both schemes, with and without Increase Contrast",
            arguments: nonText
        )
        func nonText_meetsThreeToOne(pair: ComponentColorPair) {
            for (setting, ratio) in ComponentContrastAdversarialTests.ratios(pair) {
                #expect(ratio >= pair.minimum, "\(pair.name), \(setting): \(String(format: "%.2f", ratio)):1")
            }
        }

        /// The progress bar's done and current segments also stand out from the track they sit beside
        /// in the standard settings (with Increase Contrast the track steps up and the words carry it).
        @Test(
            "ProgressSegments: done and current reach 3:1 against the upcoming track",
            arguments: [ColorScheme.light, .dark]
        )
        func progressSegments_filled_standsOutFromTheTrack(_ scheme: ColorScheme) {
            let ground = ComponentContrastAdversarialTests.resolve(LedgerColor.ground, scheme, increased: false)
            let track = ComponentContrastAdversarialTests.resolve(LedgerColor.hairlineStrong, scheme, increased: false)
                .composited(over: ground)
            for (name, color) in [("done", LedgerColor.inkMuted), ("current", LedgerColor.accentText)] {
                let ratio = ComponentContrastAdversarialTests.resolve(color, scheme, increased: false)
                    .composited(over: ground)
                    .contrast(on: track)
                #expect(ratio >= 3, "\(name) on the track, \(scheme): \(String(format: "%.2f", ratio)):1")
            }
        }
    }
#endif
