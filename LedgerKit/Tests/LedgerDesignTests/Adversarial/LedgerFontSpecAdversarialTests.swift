import LedgerDesign
import SwiftUI
import Testing

/// What spec §8.5 (v2 roles, watch roles) and the v2 / watch prototypes allow for one role.
/// Ranges are used only where the spec itself gives one ("card title 600 25–27px").
nonisolated struct RoleExpectation: Sendable, CustomTestStringConvertible {
    let role: LedgerFont.Role
    let size: ClosedRange<CGFloat>
    let weight: ClosedRange<CGFloat>
    let width: CGFloat
    let tracking: ClosedRange<CGFloat>
    let lineHeight: ClosedRange<CGFloat>?
    let uppercase: Bool
    let tabular: Bool

    var testDescription: String {
        "\(role)"
    }

    init(
        _ role: LedgerFont.Role,
        size: ClosedRange<CGFloat>,
        weight: ClosedRange<CGFloat>,
        width: CGFloat = 100,
        tracking: ClosedRange<CGFloat> = exactly(0),
        line: ClosedRange<CGFloat>? = exactly(1),
        uppercase: Bool = false,
        tabular: Bool = false
    ) {
        self.role = role
        self.size = size
        self.weight = weight
        self.width = width
        self.tracking = tracking
        lineHeight = line
        self.uppercase = uppercase
        self.tabular = tabular
    }

    /// Watch prototype px → device pt (§4.1: drawn at 1.5× a 46 mm display).
    static func watchPoints(_ pixels: CGFloat) -> ClosedRange<CGFloat> {
        let points = pixels / 1.5
        return points - 0.01 ... points + 0.01
    }

    static func exactly(_ value: CGFloat) -> ClosedRange<CGFloat> {
        value - 0.001 ... value + 0.001
    }

    /// One row per role, each quoting the prototype declaration it comes from.
    static let all: [Self] = phone + numerals + watch

    static let phone: [Self] = [
        // Onboarding h2 `600 38px/1.06 'wdth' 98 -.035em`
        .init(
            .display,
            size: exactly(38),
            weight: exactly(600),
            width: 98,
            tracking: exactly(-0.035),
            line: exactly(1.06)
        ),
        // Screen title h2 `600 32px/1 'wdth' 98 -.035em`
        .init(.title, size: exactly(32), weight: exactly(600), width: 98, tracking: exactly(-0.035)),
        // Card title `600 25–27px wdth 98 −.03em` (Up-next 25/1.15, exercise 27/1.08 −.032em)
        .init(
            .heading,
            size: 25 ... 27,
            weight: exactly(600),
            width: 98,
            tracking: -0.032 ... -0.03,
            line: 1.08 ... 1.15
        ),
        // Sheet title h4 `600 21px/1.1 'wdth' 98 -.03em`
        .init(
            .subheading,
            size: exactly(21),
            weight: exactly(600),
            width: 98,
            tracking: exactly(-0.03),
            line: exactly(1.1)
        ),
        // Row titles `500 15–16px/1.2`
        .init(.body, size: 15 ... 16, weight: exactly(500), line: exactly(1.2)),
        // Body `300 13–15.5px`, paragraphs `/1.45–1.6`
        .init(.bodyLight, size: 13 ... 15.5, weight: exactly(300), line: 1.45 ... 1.6),
        // Meta `300 12.5px/1.2–1.35`
        .init(.label, size: exactly(12.5), weight: exactly(300), line: 1.2 ... 1.35),
        // Primary CTA `600 16px/1 -.005em`
        // F06 fix round: 700 (v1's CTA weight) so white on the accent meets the bold-text 3:1 rule.
        .init(.button, size: exactly(16), weight: exactly(700), tracking: exactly(-0.005)),
        // Labels `500 10px/1 .18em` uppercase (UP NEXT, RECENT, …)
        .init(.eyebrow, size: exactly(10), weight: exactly(500), tracking: exactly(0.18), uppercase: true)
    ]

    static let numerals: [Self] = [
        // Stat numbers `700 30–34px/1 wdth 88 −.03em` tabular
        .init(.numeralXL, size: exactly(34), weight: exactly(700), width: 88, tracking: exactly(-0.03), tabular: true),
        .init(.numeralL, size: exactly(30), weight: exactly(700), width: 88, tracking: exactly(-0.03), tabular: true),
        // Set numbers `700 24px/1 'wdth' 90 -.025em` tabular
        .init(.numeralM, size: exactly(24), weight: exactly(700), width: 90, tracking: exactly(-0.025), tabular: true),
        // PR values `700 15px/1 'wdth' 90` tabular
        .init(.numeralS, size: exactly(15), weight: exactly(700), width: 90, tabular: true)
    ]

    static let watch: [Self] = [
        // Weight `700 64px/.86 'wdth' 92 -.035em` tabular
        .init(
            .watchNumeral, size: watchPoints(64), weight: exactly(700), width: 92,
            tracking: exactly(-0.035), line: exactly(0.86), tabular: true
        ),
        // Countdown / summary elapsed `700 52px/1 'wdth' 92 -.035em` tabular
        .init(
            .watchCountdown,
            size: watchPoints(52),
            weight: exactly(700),
            width: 92,
            tracking: exactly(-0.035),
            tabular: true
        ),
        // Summary stats `700 30px/1 'wdth' 92 -.03em` tabular
        .init(
            .watchStat,
            size: watchPoints(30),
            weight: exactly(700),
            width: 92,
            tracking: exactly(-0.03),
            tabular: true
        ),
        // Exercise name `600 20px/1.12`
        .init(.watchTitle, size: watchPoints(20), weight: exactly(600), line: exactly(1.12)),
        // Buttons `600–700 18–21px`
        .init(.watchButton, size: 11.99 ... 14.01, weight: 600 ... 700, tracking: -0.01 ... 0, line: nil),
        // Labels `700 17px .08–.1em` uppercase
        .init(.watchLabel, size: watchPoints(17), weight: exactly(700), tracking: 0.08 ... 0.1, uppercase: true),
        // Captions `600 17px .07em` uppercase (ELAPSED, SETS, LB MOVED)
        .init(.watchCaption, size: watchPoints(17), weight: exactly(600), tracking: exactly(0.07), uppercase: true)
    ]
}

@Suite("LedgerFont roles (adversarial)", .tags(.design))
nonisolated struct LedgerFontSpecAdversarialTests {
    @Test(
        "Each role's size, weight, width, tracking, line height, case and figures follow spec §8.5.",
        arguments: RoleExpectation.all
    )
    func role_spec_matchesPrototype(expected: RoleExpectation) {
        let spec = expected.role.spec
        #expect(expected.size.contains(spec.size), "size \(spec.size), spec \(expected.size)")
        #expect(expected.weight.contains(spec.weight), "wght \(spec.weight), spec \(expected.weight)")
        #expect(abs(spec.width - expected.width) < 0.001, "wdth \(spec.width), spec \(expected.width)")
        #expect(expected.tracking.contains(spec.tracking), "tracking \(spec.tracking)em, spec \(expected.tracking)")
        if let lineHeight = expected.lineHeight {
            #expect(lineHeight.contains(spec.lineHeight), "line height \(spec.lineHeight), spec \(lineHeight)")
        }
        #expect(spec.isUppercase == expected.uppercase)
        #expect(spec.isTabular == expected.tabular)
    }

    @Test(
        "The brief's numeral rule holds for every numeral role: wght 700, wdth 88–92, tabular.",
        arguments: [LedgerFont.Role.numeralXL, .numeralL, .numeralM, .numeralS, .watchNumeral]
    )
    func numeralRole_isHeavyNarrowTabular(role: LedgerFont.Role) {
        let spec = role.spec
        #expect(spec.weight == 700)
        #expect((88 ... 92).contains(spec.width))
        #expect(spec.isTabular)
    }

    @Test(
        "Every role's design size is at or above its own floor, and watch roles floor at 11 pt.",
        arguments: LedgerFont.Role.allCases
    )
    func role_designSize_respectsFloor(role: LedgerFont.Role) {
        let spec = role.spec
        #expect(spec.size >= spec.minimumSize)
        if role.rawValue.hasPrefix("watch") {
            #expect(spec.minimumSize >= 11, "criterion 4: no watch label below 11 pt")
        }
    }

    @Test(
        "Axis values stay inside the design's own ranges: wght 300…700, wdth 88…112 (brief).",
        arguments: LedgerFont.Role.allCases
    )
    func role_axes_stayInDesignRange(role: LedgerFont.Role) {
        #expect((300 ... 700).contains(role.spec.weight))
        #expect((88 ... 112).contains(role.spec.width))
    }
}
