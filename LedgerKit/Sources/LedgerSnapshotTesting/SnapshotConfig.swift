import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// The one place snapshot tolerances and the device/appearance matrix are defined
/// (docs/testing-strategy.md §2.5). Tests never override these per call.
public nonisolated enum SnapshotConfig {
    /// Fraction of pixels that must match.
    public static let precision: Float = 0.995
    /// How close a pixel must be to count as matching (0.98 ≈ ΔE 2, "just noticeable").
    public static let perceptualPrecision: Float = 0.98
    /// References are rendered at 1× to keep `__Snapshots__` small (F06 brief, non-functional).
    public static let scale: CGFloat = 1
    /// iPhone 17 portrait width in points; the v2 prototype is drawn at the same 402 pt.
    public static let phoneWidth: CGFloat = 402

    /// The Dynamic Type size at which `@ScaledMetric` returns its base value: `.large` on iOS,
    /// `.xLarge` on watchOS (measured on the 26.5 simulator in F06; also the 44–49 mm default).
    /// Token and component sizes are exact here.
    public static var referenceDynamicTypeSize: DynamicTypeSize {
        #if os(watchOS)
            .xLarge
        #else
            .large
        #endif
    }

    /// The platform a reference was recorded on. It is part of every reference name because
    /// text rasterises differently on iOS and watchOS.
    public static var platform: String {
        #if os(watchOS)
            "watchOS"
        #elseif os(iOS)
            "iOS"
        #else
            "macOS"
        #endif
    }
}

/// One cell of the phone matrix: light/dark × three Dynamic Type sizes (F06 criterion 3).
public nonisolated struct SnapshotAppearance: Sendable, CustomStringConvertible {
    public let colorScheme: ColorScheme
    public let dynamicTypeSize: DynamicTypeSize

    public init(_ colorScheme: ColorScheme, _ dynamicTypeSize: DynamicTypeSize) {
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
    }

    public static let phoneMatrix: [SnapshotAppearance] = [ColorScheme.light, .dark].flatMap { scheme in
        [DynamicTypeSize.large, .xLarge, .accessibility3].map { SnapshotAppearance(scheme, $0) }
    }

    /// For example `dark-xLarge`; used in reference names.
    public var description: String {
        "\(colorScheme == .dark ? "dark" : "light")-\(dynamicTypeSize)"
    }

    #if os(iOS)
        /// Traits for swift-snapshot-testing's `.image(layout:traits:)`.
        @MainActor public var traits: UITraitCollection {
            UITraitCollection { traits in
                traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
                traits.preferredContentSizeCategory = UIContentSizeCategory(dynamicTypeSize)
                traits.displayScale = SnapshotConfig.scale
            }
        }
    #endif
}

public extension View {
    /// Puts `appearance` in SwiftUI's own environment as well as in the snapshot's traits.
    /// swift-snapshot-testing measures a `.sizeThatFits` view before it applies `traits`, so without
    /// this a sheet at `.xLarge` or `.accessibility3` is laid out in its `.large` size and clipped at
    /// the top and bottom (found in F06 fix round 3).
    func snapshotAppearance(_ appearance: SnapshotAppearance) -> some View {
        environment(\.dynamicTypeSize, appearance.dynamicTypeSize).environment(\.colorScheme, appearance.colorScheme)
    }
}

/// Watch display sizes in points (docs/testing-strategy.md §2.5). One watch simulator renders
/// all three as fixed layouts.
public nonisolated enum WatchSize: String, CaseIterable, Sendable {
    case mm42, mm46, mm49

    public var size: CGSize {
        switch self {
        case .mm42: CGSize(width: 187, height: 223)
        case .mm46: CGSize(width: 208, height: 248)
        case .mm49: CGSize(width: 205, height: 251)
        }
    }

    /// The watch's default text size (HIG, watchOS Dynamic Type sizes): `.large` on 40–42 mm,
    /// `.xLarge` on 44–49 mm.
    public var dynamicTypeSize: DynamicTypeSize {
        self == .mm42 ? .large : .xLarge
    }
}
