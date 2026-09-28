import LedgerDesign
import SwiftUI
import Testing

/// A text-on-background pair the prototypes actually draw, with the WCAG AA minimum that the
/// brief's non-functional requirement ("informational text at ≥ 4.5:1 where it carries meaning")
/// asks of it. None of these is large text (≥ 18.67 px bold or 24 px regular), so all need 4.5:1.
nonisolated struct ContrastPair: Sendable, CustomTestStringConvertible {
    let name: String
    let foreground: Color
    let background: Color
    let scheme: ColorScheme
    let minimum: Double

    var testDescription: String {
        "\(name) (\(scheme == .dark ? "dark" : "light"))"
    }

    static func both(_ name: String, _ foreground: Color, on background: Color) -> [Self] {
        [ColorScheme.light, .dark].map {
            Self(name: name, foreground: foreground, background: background, scheme: $0, minimum: 4.5)
        }
    }

    /// Phone pairs. v2 examples: `ink` = row titles, `inkSecondary` = preview names (.72),
    /// `inkMuted` = "Week 3 of 8 · ~52 min", "1RM est", "sessions this week" (.38–.45),
    /// `accentText` = "UP NEXT", "+8%", "PR", `onAccent` = every CTA label (600 16 px `#fff`).
    static let phone: [Self] =
        both("ink on ground", LedgerColor.ink, on: LedgerColor.ground)
            + both("ink on surface", LedgerColor.ink, on: LedgerColor.surface)
            + both("inkSecondary on ground", LedgerColor.inkSecondary, on: LedgerColor.ground)
            + both("inkSecondary on surface", LedgerColor.inkSecondary, on: LedgerColor.surface)
            + both("inkMuted on ground", LedgerColor.inkMuted, on: LedgerColor.ground)
            + both("inkMuted on surface", LedgerColor.inkMuted, on: LedgerColor.surface)
            + both("accentText on ground", LedgerColor.accentText, on: LedgerColor.ground)
            + both("accentText on surface", LedgerColor.accentText, on: LedgerColor.surface)
            + both("onAccent on accent", LedgerColor.onAccent, on: LedgerColor.accent)

    /// Watch pairs (§8.3): values 17 px+ (11 pt), captions "ELAPSED"/"SETS"/"LB MOVED" at .4.
    static let watch: [Self] = [
        watchPair("watchInk on watchGround", LedgerColor.watchInk, on: LedgerColor.watchGround),
        watchPair("watchInkSecondary on watchGround", LedgerColor.watchInkSecondary, on: LedgerColor.watchGround),
        watchPair("watchInkMuted on watchGround", LedgerColor.watchInkMuted, on: LedgerColor.watchGround),
        watchPair("accent on watchGround", LedgerColor.accent, on: LedgerColor.watchGround),
        watchPair("onAccent on accent (watch CTA)", LedgerColor.onAccent, on: LedgerColor.accent)
    ]

    static func watchPair(_ name: String, _ foreground: Color, on background: Color) -> Self {
        Self(name: name, foreground: foreground, background: background, scheme: .dark, minimum: 4.5)
    }
}

@Suite("Contrast (adversarial)", .tags(.design))
struct ContrastAdversarialTests {
    static func ratio(_ pair: ContrastPair) -> Double {
        let background = Resolve.color(pair.background, in: pair.scheme)
        return Resolve.color(pair.foreground, in: pair.scheme).contrast(on: background)
    }

    #if os(iOS)
        @Test(
            "Meaning-carrying phone text meets WCAG AA 4.5:1 (brief non-functional; decisions §contrast).",
            arguments: ContrastPair.phone
        )
        func phonePair_meetsAA(pair: ContrastPair) {
            let ratio = Self.ratio(pair)
            #expect(ratio >= pair.minimum, "\(pair.testDescription): \(String(format: "%.2f", ratio)):1")
        }
    #endif

    @Test("Meaning-carrying watch text meets WCAG AA 4.5:1.", arguments: ContrastPair.watch)
    func watchPair_meetsAA(pair: ContrastPair) {
        let ratio = Self.ratio(pair)
        #expect(ratio >= pair.minimum, "\(pair.testDescription): \(String(format: "%.2f", ratio)):1")
    }

    @Test("Hairlines stay visible: at least 1.1:1 against their ground, but quieter than muted text.")
    func hairline_isVisibleButQuiet() {
        for scheme in [ColorScheme.light, .dark] {
            let ground = Resolve.color(LedgerColor.ground, in: scheme)
            let hairline = Resolve.color(LedgerColor.hairline, in: scheme).contrast(on: ground)
            let strong = Resolve.color(LedgerColor.hairlineStrong, in: scheme).contrast(on: ground)
            let muted = Resolve.color(LedgerColor.inkMuted, in: scheme).contrast(on: ground)
            #expect(hairline > 1.1, "\(scheme) hairline \(hairline)")
            #expect(hairline < strong && strong < muted, "\(scheme): \(hairline) < \(strong) < \(muted)")
        }
    }
}
