import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// A watch case size with its default text size from the HIG's watchOS Dynamic Type tables:
/// Large is the default on 40/41/42 mm, Extra Large on 44/45/49 mm (46 mm follows 45 mm).
nonisolated struct WatchCase: Sendable, CustomTestStringConvertible {
    let millimetres: Int
    let defaultTextSize: DynamicTypeSize

    var testDescription: String {
        "\(millimetres) mm"
    }

    static let all = [
        Self(millimetres: 41, defaultTextSize: .large), Self(millimetres: 42, defaultTextSize: .large),
        Self(millimetres: 45, defaultTextSize: .xLarge), Self(millimetres: 46, defaultTextSize: .xLarge)
    ]
}

/// A watch text role with the prototype values that fix its reference rendering.
nonisolated struct WatchRole: Sendable, CustomTestStringConvertible {
    let role: LedgerFont.Role
    let prototypePixels: CGFloat
    let weight: CGFloat
    let width: CGFloat

    var testDescription: String {
        "\(role)"
    }

    /// The watch prototype's sizes (LedgerWatch.dc.html), 1.5× device points.
    static let all = [
        Self(role: .watchNumeral, prototypePixels: 64, weight: 700, width: 92),
        Self(role: .watchCountdown, prototypePixels: 52, weight: 700, width: 92),
        Self(role: .watchStat, prototypePixels: 30, weight: 700, width: 92),
        Self(role: .watchTitle, prototypePixels: 20, weight: 600, width: 100),
        Self(role: .watchLabel, prototypePixels: 17, weight: 700, width: 100),
        Self(role: .watchCaption, prototypePixels: 17, weight: 600, width: 100)
    ]

    /// The small text roles criterion 4's 11 pt floor protects.
    static let smallText = all.filter { $0.prototypePixels <= 20 }
}

extension RenderingSuites {
    @Suite("Watch type floor (adversarial)", .tags(.design))
    struct WatchTypeFloorAdversarialTests {
        static let scale: CGFloat = 6

        static func capHeight(_ view: some View, type: DynamicTypeSize = .large) throws -> Int {
            let buffer = try #require(Probe.inked(view, scale: scale, dynamicTypeSize: type))
            return try #require(Probe.inkHeight(buffer))
        }

        /// Cap height of an "H" in Archivo read straight from the font file.
        static func referenceCapHeight(points: CGFloat, weight: CGFloat, width: CGFloat) throws -> Int {
            _ = FontRegistration.registerIfNeeded()
            let font = try #require(ArchivoFile.swiftUIFont(size: points, weight: weight, width: width))
            return try capHeight(Text("H").font(font))
        }

        @Test(
            "Small watch text never renders below 11 pt at any text size up to the 45/46 mm default.",
            arguments: WatchRole.smallText
        )
        func smallWatchRole_smallTextSizes_neverBelowElevenPoints(role: WatchRole) throws {
            let minimum = try Self.referenceCapHeight(points: 11, weight: role.weight, width: role.width)
            for type in [DynamicTypeSize.xSmall, .small, .medium, .large, .xLarge] {
                let height = try Self.capHeight(Text("H").ledgerFont(role.role), type: type)
                #expect(height >= minimum - 1, "\(role.role) at \(type): cap \(height) px < 11 pt cap \(minimum) px")
            }
        }

        @Test(
            "At each 41/42/45/46 mm default text size, every watch role is at least 11 pt.",
            arguments: WatchCase.all
        )
        func watchCase_defaultTextSize_everyRoleAtLeastElevenPoints(watch: WatchCase) throws {
            for role in WatchRole.all {
                let minimum = try Self.referenceCapHeight(points: 11, weight: role.weight, width: role.width)
                let height = try Self.capHeight(Text("H").ledgerFont(role.role), type: watch.defaultTextSize)
                #expect(
                    height >= minimum - 1,
                    "\(watch.testDescription) \(role.role): cap \(height) px, 11 pt is \(minimum) px"
                )
            }
        }

        #if os(watchOS)
            @Test(
                "At the 46 mm default text size each watch role renders at prototype px ÷ 1.5 (spec §4.1).",
                arguments: WatchRole.all
            )
            func watchRole_46mmDefault_rendersPrototypeSize(role: WatchRole) throws {
                let points = role.prototypePixels / 1.5
                let wanted = try Self.referenceCapHeight(points: points, weight: role.weight, width: role.width)
                let height = try Self.capHeight(Text("H").ledgerFont(role.role), type: .xLarge)
                #expect(abs(height - wanted) <= 1, "\(role.role): cap \(height) px, \(points) pt is \(wanted) px")
            }

            @Test("watchOS @ScaledMetric returns its base value at .xLarge (the harness's reference size).")
            func scaledMetric_watchOS_baseIsExtraLarge() throws {
                let image = try #require(Probe.image(ScaledProbe(), dynamicTypeSize: .xLarge))
                #expect(image.width == 100, "a 100 pt @ScaledMetric renders \(image.width) pt at .xLarge")
                #expect(SnapshotConfig.referenceDynamicTypeSize == .xLarge)
            }
        #endif

        #if os(iOS)
            @Test("iOS @ScaledMetric returns its base value at .large (the harness's reference size).")
            func scaledMetric_iOS_baseIsLarge() throws {
                let image = try #require(Probe.image(ScaledProbe(), dynamicTypeSize: .large))
                #expect(image.width == 100)
                #expect(SnapshotConfig.referenceDynamicTypeSize == .large)
            }
        #endif

        @Test(
            "The explicit-size entry point keeps the 11 pt floor too: \"the size never scales below\" it.",
            arguments: WatchRole.smallText
        )
        func smallWatchRole_explicitSmallSize_neverBelowElevenPoints(role: WatchRole) throws {
            let minimum = try Self.referenceCapHeight(points: 11, weight: role.weight, width: role.width)
            let height = try Self.capHeight(Text("H").font(LedgerFont.font(role.role, size: 9)))
            #expect(height >= minimum - 1, "\(role.role) at an explicit 9 pt: cap \(height) px, 11 pt is \(minimum) px")
        }

        @Test("The harness's watch sizes and default text sizes match the HIG (testing-strategy §2.5).")
        func watchSize_harness_matchesHIG() {
            #expect(WatchSize.mm42.size == CGSize(width: 187, height: 223))
            #expect(WatchSize.mm46.size == CGSize(width: 208, height: 248))
            #expect(WatchSize.mm49.size == CGSize(width: 205, height: 251))
            #expect(WatchSize.mm42.dynamicTypeSize == .large)
            #expect(WatchSize.mm46.dynamicTypeSize == .xLarge)
            #expect(WatchSize.mm49.dynamicTypeSize == .xLarge)
        }
    }
}

/// A 100 pt wide strip whose width follows `@ScaledMetric`, to find the size where it is unscaled.
private struct ScaledProbe: View {
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 100

    var body: some View {
        Color.white.frame(width: side, height: 1)
    }
}
