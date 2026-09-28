import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Round 2: the explicit-size font API that replaced `font(_:)` — `scaledSize(_:dynamicTypeSize:)`,
/// `font(_:dynamicTypeSize:legibilityWeight:)` and `font(_:size:legibilityWeight:)` — against
/// SwiftUI's own custom-metric curve (`@ScaledMetric`), the 11 pt watch floor and `.ledgerFont`.
@Suite("LedgerFont sizing (adversarial, round 2)", .tags(.design))
struct LedgerFontSizingAdversarialTests {
    /// macOS (`swift test` on the host) has no Dynamic Type; the simulators are the truth.
    static var hasDynamicType: Bool {
        #if os(iOS) || os(watchOS)
            true
        #else
            false
        #endif
    }

    /// SwiftUI's scale factor for `style` at `size`, read from a 1000 pt `@ScaledMetric`.
    static func scaledMetricFactor(_ style: Font.TextStyle, at size: DynamicTypeSize) throws -> CGFloat {
        let image = try #require(Probe.image(ScaledValueProbe(base: 1000, relativeTo: style), dynamicTypeSize: size))
        return CGFloat(image.width) / 1000
    }

    @Test(
        "At the platform's reference text size every role is exactly its design size.",
        arguments: LedgerFont.Role.allCases
    )
    func scaledSize_referenceTextSize_isDesignSize(role: LedgerFont.Role) {
        let size = LedgerFont.scaledSize(role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
        #expect(abs(size - role.spec.size) < 0.01, "\(role): \(size) pt, design \(role.spec.size) pt")
    }

    @Test(
        "Every role follows SwiftUI's @ScaledMetric curve for its text style at all 12 sizes (floor applied).",
        arguments: LedgerFont.Role.allCases
    )
    func scaledSize_everyTextSize_followsScaledMetric(role: LedgerFont.Role) throws {
        let spec = role.spec
        for type in DynamicTypeSize.allCases {
            let factor = try Self.scaledMetricFactor(spec.textStyle, at: type)
            let expected = max(spec.size * factor, spec.minimumSize)
            let actual = LedgerFont.scaledSize(role, dynamicTypeSize: type)
            #expect(
                abs(actual - expected) <= spec.size * 0.002 + 0.01,
                "\(role) at \(type): \(actual), curve \(expected)"
            )
        }
    }

    @Test(
        "No role shrinks as the text size grows, none is capped, and none falls below its floor.",
        arguments: LedgerFont.Role.allCases
    )
    func scaledSize_acrossTextSizes_monotonicUncappedFloored(role: LedgerFont.Role) {
        let sizes = DynamicTypeSize.allCases.map { LedgerFont.scaledSize(role, dynamicTypeSize: $0) }
        #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0 <= $1 + 0.001 }, "\(role): \(sizes)")
        #expect(sizes.allSatisfy { $0 >= role.spec.minimumSize - 0.001 })
        if role.rawValue.hasPrefix("watch") {
            #expect(sizes.allSatisfy { $0 >= 11 - 0.001 }, "\(role): \(sizes)")
        }
        let reference = LedgerFont.scaledSize(role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
        let largest = LedgerFont.scaledSize(role, dynamicTypeSize: .accessibility5)
        if Self.hasDynamicType {
            #expect(largest > reference * 1.1, "\(role): \(reference) → \(largest) pt at AX5")
        }
    }

    @Test(
        "The explicit-size font never goes below the role's floor, however small the request.",
        arguments: LedgerFont.Role.allCases.filter { $0.spec.minimumSize > 1 }
    )
    func explicitSize_belowFloor_rendersAtFloor(role: LedgerFont.Role) throws {
        let floorSize = role.spec.minimumSize
        let atFloor = try #require(Probe.inked(Text("H").font(LedgerFont.font(role, size: floorSize)), scale: 4))
        for request in [floorSize - 0.5, 9, 1] where request < floorSize {
            let clamped = try #require(Probe.inked(Text("H").font(LedgerFont.font(role, size: request)), scale: 4))
            #expect(clamped == atFloor, "\(role) asked for \(request) pt")
        }
    }

    /// White on black with a wide margin: `.ledgerFont`'s line height can put ink outside the frame
    /// (see LedgerFontLineBoxAdversarialTests), and this comparison is about the font, not the frame.
    static func inkedWithMargin(_ text: some View, type: DynamicTypeSize) -> PixelBuffer? {
        Probe.buffer(
            text.foregroundStyle(Color.white).padding(60).background(Color.black),
            scale: 2, dynamicTypeSize: type
        )
    }

    @Test(
        "font(role, dynamicTypeSize:legibilityWeight:) draws what .ledgerFont draws in that environment.",
        arguments: LedgerFont.Role.allCases
    )
    func bareFont_everySizeAndWeight_matchesLedgerFont(role: LedgerFont.Role) throws {
        for type in DynamicTypeSize.allCases {
            for weight in [LegibilityWeight.regular, .bold] {
                let bare = Text("H").font(LedgerFont.font(role, dynamicTypeSize: type, legibilityWeight: weight))
                let styled = Text("H").ledgerFont(role).environment(\.legibilityWeight, weight)
                let expected = try #require(Self.inkedWithMargin(bare, type: type))
                let actual = try #require(Self.inkedWithMargin(styled, type: type))
                #expect(Probe.inkHeight(actual) == Probe.inkHeight(expected), "\(role) \(type) \(weight): height")
                #expect(Probe.inkCount(actual) == Probe.inkCount(expected), "\(role) \(type) \(weight): ink")
            }
        }
    }

    @Test("A nil legibility weight is the regular weight.", arguments: LedgerFont.Role.allCases)
    func bareFont_nilLegibilityWeight_isRegular(role: LedgerFont.Role) throws {
        let type = SnapshotConfig.referenceDynamicTypeSize
        let unset = try #require(Probe.inked(
            Text("Hg 185").font(LedgerFont.font(role, dynamicTypeSize: type)),
            scale: 2
        ))
        let regular = try #require(Probe.inked(
            Text("Hg 185").font(LedgerFont.font(role, dynamicTypeSize: type, legibilityWeight: .regular)), scale: 2
        ))
        #expect(unset == regular)
    }

    @Test(".ledgerFont re-reads the environment when it changes under the same view (no cached size or weight).")
    func ledgerFont_environmentChangesInPlace_restyles() throws {
        let renderer = ImageRenderer(content: Self.probe(.large, .regular))
        renderer.scale = 2
        let large = try #require(renderer.cgImage.flatMap(PixelBuffer.init))
        renderer.content = Self.probe(.accessibility3, .regular)
        let accessibility = try #require(renderer.cgImage.flatMap(PixelBuffer.init))
        renderer.content = Self.probe(.accessibility3, .bold)
        let bold = try #require(renderer.cgImage.flatMap(PixelBuffer.init))
        renderer.content = Self.probe(.large, .regular)
        let back = try #require(renderer.cgImage.flatMap(PixelBuffer.init))
        if Self.hasDynamicType {
            #expect((Probe.inkHeight(accessibility) ?? 0) > (Probe.inkHeight(large) ?? 0) + 4, "no growth at AX3")
        }
        #expect(Probe.inkCount(bold) > Probe.inkCount(accessibility), "no weight change with Bold Text")
        #expect(back == large, "returning to .large did not restore the first rendering")
    }

    static func probe(_ type: DynamicTypeSize, _ weight: LegibilityWeight) -> some View {
        Text("H").ledgerFont(.body)
            .foregroundStyle(Color.white).padding(8).background(Color.black)
            .environment(\.dynamicTypeSize, type)
            .environment(\.legibilityWeight, weight)
    }
}

/// A `base`-point strip whose width follows `@ScaledMetric` relative to `style`.
private struct ScaledValueProbe: View {
    @ScaledMetric private var value: CGFloat

    init(base: CGFloat, relativeTo style: Font.TextStyle) {
        _value = ScaledMetric(wrappedValue: base, relativeTo: style)
    }

    var body: some View {
        Color.white.frame(width: value, height: 1)
    }
}
