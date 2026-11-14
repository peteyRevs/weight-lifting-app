#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import UIKit

    /// Asserts `view` against its reference in one cell of the phone matrix. Every phone snapshot goes
    /// through here, so none can leave a step out (F06 review S1): the appearance is applied with
    /// `snapshotAppearance(_:)` (SwiftUI's environment, the view's own height) and as traits, and the image is
    /// compared with ``SnapshotConfig``'s pixel budget (`Snapshotting.phone`). `name` defaults to the appearance
    /// (`dark-xLarge`); `modifyingTraits` adds traits on top of the appearance's, for example Increase Contrast.
    public func assertPhoneSnapshot(
        of view: some View,
        _ appearance: SnapshotAppearance,
        named name: String? = nil,
        modifyingTraits: (inout any UIMutableTraits) -> Void = { _ in },
        fileID: StaticString = #file,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let page = PhonePage(view, appearance)
        assertSnapshot(
            of: page,
            as: .phone(appearance, modifyingTraits: modifyingTraits),
            named: name ?? appearance.description,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    /// `view` at `appearance` (`snapshotAppearance(_:)`) in a frame of the size it is drawn at.
    ///
    /// swift-snapshot-testing's `.sizeThatFits` measures the view on the simulator's 3× screen, where SwiftUI
    /// rounds each view's size to a third of a point, and the image is drawn at `SnapshotConfig.scale` (1×),
    /// where each is rounded to a whole point. A stack of text grew by up to two thirds of a point a line and was
    /// drawn centred in the shorter image, cut 1 to 23 pt at each end (`tasks/chores/2026-10-12-m1-batch-b.md`
    /// §4 b). So the page is measured hosted in a window whose display scale is the drawing's, and framed to that.
    public struct PhonePage: View {
        let content: AnyView
        let size: CGSize

        public init(_ view: some View, _ appearance: SnapshotAppearance) {
            content = AnyView(view.snapshotAppearance(appearance))
            size = Self.drawnSize(of: content)
        }

        public var body: some View {
            content.frame(width: size.width, height: size.height)
        }

        static func drawnSize(of view: AnyView) -> CGSize {
            let host = UIHostingController(rootView: view)
            host.safeAreaRegions = []
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.traitOverrides.displayScale = SnapshotConfig.scale
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let measured = host.sizeThatFits(in: .zero)
            let scale = SnapshotConfig.scale
            return CGSize(
                width: (measured.width * scale).rounded(.up) / scale,
                height: (measured.height * scale).rounded(.up) / scale
            )
        }
    }

    public extension Snapshotting where Value == PhonePage, Format == UIImage {
        /// The strategy `assertPhoneSnapshot` compares a page with: drawn at `appearance`'s traits (plus
        /// `modifyingTraits`) at the page's own size, and compared within ``SnapshotConfig/pixelBudget``.
        static func phone(
            _ appearance: SnapshotAppearance,
            modifyingTraits: (inout any UIMutableTraits) -> Void = { _ in }
        ) -> Snapshotting {
            var strategy = Snapshotting.image(
                perceptualPrecision: SnapshotConfig.perceptualPrecision,
                layout: .sizeThatFits,
                traits: appearance.traits.modifyingTraits(modifyingTraits)
            )
            strategy.diffing = .withinPixelBudget
            return strategy
        }
    }

    public extension Diffing where Value == UIImage {
        /// swift-snapshot-testing's image comparison, at the precision that lets ``SnapshotConfig/pixelBudget``
        /// pixels of the reference differ (``SnapshotConfig/precision(pixels:)``), whatever its size.
        static var withinPixelBudget: Diffing {
            let fixed = Diffing.image(scale: SnapshotConfig.scale)
            return .diff(toData: fixed.toData, fromData: fixed.fromData) { reference, actual in
                let pixels = Int(reference.size.width * reference.scale) * Int(reference.size.height * reference.scale)
                let precision = SnapshotConfig.precision(pixels: pixels)
                let comparison = Diffing.image(
                    precision: precision, perceptualPrecision: SnapshotConfig.perceptualPrecision,
                    scale: SnapshotConfig.scale
                )
                return comparison.diffV2(reference, actual).map { message, attachments in
                    ("At most \(SnapshotConfig.pixelBudget) of \(pixels) pixels may differ: \(message)", attachments)
                }
            }
        }
    }
#endif
