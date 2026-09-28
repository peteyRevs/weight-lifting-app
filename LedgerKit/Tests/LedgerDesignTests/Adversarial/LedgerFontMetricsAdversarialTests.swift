import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Letter spacing and line height as rendered by `.ledgerFont`, measured against the CSS the
/// prototypes use: `letter-spacing` in em per character, `line-height` as a multiple of the size
/// (baseline-to-baseline distance). Measured at the size where `.ledgerFont` equals the design size
/// (`.large` on iOS; the 46 mm default `.xLarge` for watch roles on watchOS, §4.1).
@Suite("LedgerFont metrics (adversarial)", .tags(.design))
struct LedgerFontMetricsAdversarialTests {
    static let scale: CGFloat = 4

    /// Extra width in points `.ledgerFont` adds over the bare font for the same string.
    static func trackingGain(_ text: String, role: LedgerFont.Role, type: DynamicTypeSize) throws -> CGFloat {
        let tracked = try #require(Probe.image(Text(text).ledgerFont(role), scale: scale, dynamicTypeSize: type))
        let bare = try #require(Probe.image(
            Text(text).font(LedgerFont.font(role)),
            scale: scale,
            dynamicTypeSize: type
        ))
        return CGFloat(tracked.width - bare.width) / scale
    }

    /// Baseline-to-baseline distance in points of two lines of "H".
    static func linePitch(role: LedgerFont.Role, type: DynamicTypeSize) throws -> CGFloat {
        let buffer = try #require(Probe.inked(Text("H\nH").ledgerFont(role), scale: scale, dynamicTypeSize: type))
        let runs = Probe.inkRuns(buffer)
        try #require(runs.count == 2, "expected two lines of ink, found \(runs.count)")
        return CGFloat(runs[1].lowerBound - runs[0].lowerBound) / scale
    }

    /// `n` letters under CSS letter-spacing gain (n − 1)…n × em × size (trailing space may be trimmed).
    static func expectedGain(letters: Int, ems: CGFloat, size: CGFloat) -> ClosedRange<CGFloat> {
        let perLetter = ems * size
        let bounds = [CGFloat(letters - 1) * perLetter, CGFloat(letters) * perLetter]
        return (bounds.min() ?? 0) - 0.5 ... (bounds.max() ?? 0) + 0.5
    }

    #if os(iOS)
        @Test("Eyebrows are spaced .18em: twelve capitals at 10 pt gain 19.8–21.6 pt (spec §8.5).")
        func eyebrow_tracking_isPointEighteenEm() throws {
            let gain = try Self.trackingGain("UPNEXTRECENT", role: .eyebrow, type: .large)
            let expected = Self.expectedGain(letters: 12, ems: 0.18, size: 10)
            #expect(expected.contains(gain), "gained \(gain) pt, CSS \(expected)")
        }

        @Test("Stat numerals are spaced −.03em: ten digits at 30 pt lose 8.1–9 pt (spec §8.5).")
        func numeralL_tracking_isMinusPointZeroThreeEm() throws {
            let gain = try Self.trackingGain("0000000000", role: .numeralL, type: .large)
            let expected = Self.expectedGain(letters: 10, ems: -0.03, size: 30)
            #expect(expected.contains(gain), "gained \(gain) pt, CSS \(expected)")
        }

        @Test(
            "Phone roles space lines at the prototype's CSS line-height × size.",
            arguments: RoleExpectation.phone + RoleExpectation.numerals
        )
        func phoneRole_linePitch_matchesCSSLineHeight(expected: RoleExpectation) throws {
            let multiple = try #require(expected.lineHeight)
            let size = expected.role.spec.size
            let pitch = try Self.linePitch(role: expected.role, type: .large)
            let wanted = (multiple.lowerBound * size - 0.5) ... (multiple.upperBound * size + 0.5)
            #expect(wanted.contains(pitch), "\(expected.role): \(pitch) pt between baselines, CSS \(wanted)")
        }
    #endif

    #if os(watchOS)
        @Test("Watch labels are spaced .08–.1em at 11.33 pt (watch prototype).")
        func watchLabel_tracking_isPointOneEm() throws {
            let gain = try Self.trackingGain("ELAPSED", role: .watchLabel, type: .xLarge)
            let low = Self.expectedGain(letters: 7, ems: 0.08, size: 17 / 1.5)
            let high = Self.expectedGain(letters: 7, ems: 0.1, size: 17 / 1.5)
            #expect((low.lowerBound ... high.upperBound).contains(gain), "gained \(gain) pt")
        }

        @Test(
            "Watch roles space lines at the prototype's CSS line-height × size at 46 mm.",
            arguments: RoleExpectation.watch.filter { $0.lineHeight != nil }
        )
        func watchRole_linePitch_matchesCSSLineHeight(expected: RoleExpectation) throws {
            let multiple = try #require(expected.lineHeight)
            let size = (expected.size.lowerBound + expected.size.upperBound) / 2
            let pitch = try Self.linePitch(role: expected.role, type: .xLarge)
            let wanted = (multiple.lowerBound * size - 0.5) ... (multiple.upperBound * size + 0.5)
            #expect(wanted.contains(pitch), "\(expected.role): \(pitch) pt between baselines, CSS \(wanted)")
        }
    #endif
}
