#if os(iOS)
    import LedgerDesign
    import SwiftUI
    import Testing

    /// F09 S5 adversarial round 1 (G2): what stands behind the system audit's "Dynamic Type font sizes are
    /// partially unsupported" on Today's eyebrows ("RECENT", "UP NEXT", "SCHEDULED REST"). The eyebrow follows
    /// the system's Caption 2 curve, which is flat below the default text size: the system's own Caption 2 is
    /// 11 pt at every size from Extra Small to Large. So the eyebrow does not shrink below the default and
    /// grows at every size above it, which is the "partial" the audit sees. Nothing is unsupported: this pins
    /// the curve, so that the exclusion in `TabsAdversarial` (round 2) stays true to the code.
    @Suite("Adversarial F09 S5 · the eyebrow across text sizes")
    struct EyebrowDynamicTypeAdversarialTests {
        static let sizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        @Test("The eyebrow keeps its design size up to the default text size and grows at every size above it")
        func eyebrow_isFlatBelowTheDefault_andGrowsAboveIt() {
            let points = Self.sizes.map { LedgerFont.scaledSize(.eyebrow, dynamicTypeSize: $0) }
            #expect(points.prefix(4) == [10, 10, 10, 10], "\(points)")
            let above = Array(points.dropFirst(3))
            #expect(zip(above, above.dropFirst()).allSatisfy { $0 < $1 }, "\(points)")
            #expect((points.last ?? 0) >= 20, "at the largest size it is at least twice the design size: \(points)")
        }

        @Test("The caption, which the audit does not report, shrinks below the default: its curve is not flat there")
        func caption_shrinksBelowTheDefault() {
            let points = Self.sizes.map { LedgerFont.scaledSize(.caption, dynamicTypeSize: $0) }
            #expect(points[0] < points[3], "\(points)")
            #expect(points[3] == 12, "\(points)")
        }
    }
#endif
