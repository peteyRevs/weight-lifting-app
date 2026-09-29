import Foundation
import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Round 4: fix round 3's `snapshotAppearance(_:)`, which puts the text size and colour scheme in
    /// SwiftUI's environment because swift-snapshot-testing measures a `.sizeThatFits` view before it
    /// applies `traits`. Beyond the matrix (AX5), and whether the sheet is laid out as the app lays it
    /// out; on the watch, every snapshot sheet at 42, 46 and 49 mm and at accessibility sizes.
    @Suite("Snapshot appearance (adversarial, round 4)", .tags(.design, .snapshot))
    struct SnapshotAppearanceAdversarialTests {
        /// Rows between each edge and the nearest ink, ink being anything unlike the top-left pixel (the
        /// sheet's ground).
        static func inkMargins(_ image: CGImage) throws -> (top: Int, bottom: Int) {
            let buffer = try #require(PixelBuffer(image))
            let ground = buffer.pixel(column: 0, row: 0)
            let inked = (0 ..< buffer.height).filter { row in
                (0 ..< buffer.width).contains { buffer.pixel(column: $0, row: row).differs(from: ground, by: 24) }
            }
            let first = try #require(inked.first, "no ink")
            let last = try #require(inked.last, "no ink")
            return (first, buffer.height - 1 - last)
        }

        #if os(iOS)
            nonisolated static let phoneSizes: [DynamicTypeSize] = [.large, .xLarge, .accessibility3, .accessibility5]

            static func phoneRamp(_ appearance: SnapshotAppearance) -> some View {
                TypeRampSpecimen(roles: Specimen.phoneRoles, width: SnapshotConfig.phoneWidth)
                    .snapshotAppearance(appearance)
            }

            /// The image `assertSnapshot(of:as: .image(layout: .sizeThatFits, traits:))` compares.
            static func strategyImage(_ view: some View, _ appearance: SnapshotAppearance) async throws -> CGImage {
                let strategy = Snapshotting<AnyView, UIImage>.image(layout: .sizeThatFits, traits: appearance.traits)
                let image = await withCheckedContinuation { continuation in
                    strategy.snapshot(AnyView(view)).run { continuation.resume(returning: $0) }
                }
                return try #require(image.cgImage)
            }

            @Test(
                "The phone type ramp as the snapshot strategy lays it out keeps its padding up to AX5.",
                arguments: phoneSizes
            )
            func phoneRamp_strategyLayout_notClipped(type: DynamicTypeSize) async throws {
                let appearance = SnapshotAppearance(.dark, type)
                let image = try await Self.strategyImage(Self.phoneRamp(appearance), appearance)
                let margins = try Self.inkMargins(image)
                #expect(
                    margins.top >= 8 && margins.bottom >= 8,
                    "\(appearance): ink \(margins.top) px from the top, \(margins.bottom) px from the bottom"
                )
            }

            /// Finding 24. swift-snapshot-testing sizes a `.sizeThatFits` view with
            /// `UIHostingController.sizeThatFits(in: .zero)`, a zero height proposal, so text that needs a
            /// second line is cut to one line with "…" instead of wrapping as it does on a screen.
            /// The same strategy with `.fixedSize(horizontal: false, vertical: true)` lays the sheet out at
            /// its own height: same renderer, same traits, so the heights compare exactly.
            @Test(
                "The phone type ramp as the snapshot strategy lays it out is its own height: text wraps, is not cut.",
                arguments: phoneSizes
            )
            func phoneRamp_strategyLayout_takesIdealHeight(type: DynamicTypeSize) async throws {
                let appearance = SnapshotAppearance(.dark, type)
                let snapshot = try await Self.strategyImage(Self.phoneRamp(appearance), appearance)
                let ideal = try await Self.strategyImage(
                    Self.phoneRamp(appearance).fixedSize(horizontal: false, vertical: true),
                    appearance
                )
                #expect(
                    snapshot.height == ideal.height,
                    """
                    \(appearance): the snapshot is \(snapshot.height) px tall, the sheet at its own height \
                    \(ideal.height) px; the difference is text cut to one line with "…"
                    """
                )
                if snapshot.height != ideal.height {
                    Attachment.record(Bitmap.png(snapshot), named: "snapshot-\(appearance).png")
                    Attachment.record(Bitmap.png(ideal), named: "ownHeight-\(appearance).png")
                }
            }
        #endif

        nonisolated static let watchCases: [(WatchSize, DynamicTypeSize)] = WatchSize.allCases.map {
            ($0, $0.dynamicTypeSize)
        } + [(.mm46, .accessibility3), (.mm46, .accessibility5)]

        @Test(
            "Every watch snapshot sheet keeps its padding at 42, 46 and 49 mm and at AX3 and AX5: nothing is clipped.",
            arguments: watchCases
        )
        func watchSheets_everySizeAndTextSize_notClipped(watch: WatchSize, type: DynamicTypeSize) throws {
            let ramp = TypeRampSpecimen(
                roles: Specimen.watchRoles, width: watch.size.width,
                ground: LedgerColor.watchGround, ink: LedgerColor.watchInk, nameInk: LedgerColor.watchInkMuted
            )
            let palette = PaletteSpecimen(
                swatches: PaletteSpecimen.watch, width: watch.size.width,
                ground: LedgerColor.watchGround, ink: LedgerColor.watchInk
            )
            let sheets: [(String, CGImage?)] = [
                ("type ramp", RenderedImage.render(ramp, dynamicTypeSize: type)),
                (
                    "bold type ramp",
                    RenderedImage.render(ramp.environment(\.legibilityWeight, .bold), dynamicTypeSize: type)
                ),
                ("palette", RenderedImage.render(palette, dynamicTypeSize: type))
            ]
            for (name, image) in sheets {
                let margins = try Self.inkMargins(#require(image, "\(name) did not render"))
                #expect(
                    margins.top >= 8 && margins.bottom >= 8,
                    """
                    \(name), \(watch.rawValue) at \(type): ink \(margins.top) px from the top, \
                    \(margins.bottom) px from the bottom
                    """
                )
            }
        }
    }
}
