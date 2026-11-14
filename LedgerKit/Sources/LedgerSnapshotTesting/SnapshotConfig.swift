import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// The one place snapshot tolerances and the device/appearance matrix are defined
/// (docs/testing-strategy.md §2.5). Tests never override these per call.
public nonisolated enum SnapshotConfig {
    /// How many pixels of an image may differ from its reference (beyond `perceptualPrecision`), whatever the
    /// image's size, so a long page is held as tightly as a short one. It replaced a fraction (0.995) that let a
    /// 1,009 pt cover pass with a new 44 pt button drawn (F10 review SF3: that button is
    /// 204 pixels). Chosen on 2026-11-14 from runs at a budget of 0 on the iPhone 17 (iOS 27.0) and Apple Watch
    /// Series 12 (watchOS 27.0) simulators: every reference matched every pixel, serial and parallel. 8 is under
    /// the smallest real change these references have caught (16 pixels, the builder's mirrored marks), and
    /// under 0.5 % of the smallest reference (102 of a 187 × 110 watch image), so no reference is held looser.
    public static let pixelBudget = 8

    /// How many of an image's `pixels` may differ: the budget, or 0.5 % of an image too small for it (under
    /// 1,800 pixels), so a total change of a tiny image still fails.
    public static func allowedPixels(of pixels: Int) -> Int {
        min(pixelBudget, pixels * 5 / 1000)
    }

    /// The largest phone image the budget holds exactly; a larger reference fails, so split the page.
    public static let maximumPixels = 4_000_000

    /// swift-snapshot-testing's `precision` (a fraction) that lets exactly `allowedPixels(of: pixels)` differ.
    /// It sits half a pixel above that count, because the library rounds three times: `CIAreaAverage` averages
    /// in half floats (`CIFormat.Rh`), then `1 − average` and this precision are `Float`s. Measured: about
    /// 0.18 pixels of error at 3.7 million pixels, 0.3 pixels of headroom on the longest reference (3.68
    /// million), exact up to 6.03 million, and a 9-pixel change passed at 8.04 million (hence `maximumPixels`).
    public static func precision(pixels: Int) -> Float {
        Float(1 - (Double(allowedPixels(of: pixels)) + 0.5) / Double(max(pixels, 1)))
    }

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

    /// The platform a test runs on. A sheet recorded on both simulators (today only the width spike's)
    /// carries it in its reference name, because text rasterises differently on iOS and watchOS.
    /// On the Mac host (`swift test`) no reference is recorded (F06 review N3).
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
            UITraitCollection { applyTraits(to: &$0) }
        }

        /// Sets the appearance's traits: its style, its text size and the drawing's display scale.
        @MainActor func applyTraits(to traits: inout any UIMutableTraits) {
            traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            traits.preferredContentSizeCategory = UIContentSizeCategory(dynamicTypeSize)
            traits.displayScale = SnapshotConfig.scale
        }
    #endif
}

public extension View {
    /// Lays the view out as a screen would at `appearance`, for `PhonePage`, which measures the view
    /// with the cell's traits at the drawing's display scale and proposes it a zero size, as
    /// swift-snapshot-testing's `.sizeThatFits` does (`sizeThatFits(in: .zero)` in 1.19):
    /// - the text size and colour scheme also go into SwiftUI's environment, so a sheet at `.xLarge`
    ///   or `.accessibility3` is not measured at `.large` and clipped (F06 fix round 3);
    /// - the view takes its own height, so text wraps as it does on a device instead of being cut to
    ///   one line with "…" (F06 review S1, finding 24).
    ///
    /// Phone snapshot tests go through `assertPhoneSnapshot(of:_:)`, which applies this.
    func snapshotAppearance(_ appearance: SnapshotAppearance) -> some View {
        environment(\.dynamicTypeSize, appearance.dynamicTypeSize)
            .environment(\.colorScheme, appearance.colorScheme)
            .fixedSize(horizontal: false, vertical: true)
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
