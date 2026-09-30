import CoreGraphics
@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// F06 criterion 4, the 11 pt half: the watch components set text only in the watch roles (review),
/// and each of those roles is at least 11 pt at every watch text size, xSmall to AX3, including where a
/// component lets a line shrink to fit (`LedgerFont.shrinkLimit`).
@Suite("WatchTypeFloor", .tags(.design))
nonisolated struct WatchTypeFloorTests {
    /// Every watch text size (HIG, Typography: xSmall … xxxLarge and the larger accessibility sizes AX1–AX3).
    static let watchTextSizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2,
        .accessibility3
    ]
    static let watchRoles = LedgerFont.Role.allCases.filter { $0.rawValue.hasPrefix("watch") }

    @Test(
        "Every watch role is at least 11 pt at every watch text size, and so is the smallest it may shrink to",
        .simulatorOnly,
        arguments: watchRoles
    )
    func watchRole_everyWatchTextSize_neverBelowElevenPoints(_ role: LedgerFont.Role) {
        for textSize in Self.watchTextSizes {
            let points = LedgerFont.scaledSize(role, dynamicTypeSize: textSize)
            let smallest = points * LedgerFont.shrinkLimit(role, size: points)
            #expect(points >= 11, "\(role) at \(textSize): \(points) pt")
            #expect(smallest >= 11 - 1e-9, "\(role) at \(textSize) may shrink to \(smallest) pt")
        }
    }

    @Test("The shrink limit is half, raised to the role's floor, and never grows text")
    func shrinkLimit_floorAndHalf_bothHold() {
        #expect(LedgerFont.shrinkLimit(.watchStat, size: 40) == 0.5)
        #expect(abs(LedgerFont.shrinkLimit(.watchStat, size: 18) - 11.0 / 18) < 1e-12)
        #expect(LedgerFont.shrinkLimit(.watchCaption, size: 11) == 1)
        #expect(LedgerFont.shrinkLimit(.watchCaption, size: 10) == 1, "a role already at its floor never shrinks")
        #expect(LedgerFont.shrinkLimit(.numeralM, size: 24) == 0.5, "phone roles have no floor: half")
    }
}

#if os(watchOS)
    extension RenderingSuites {
        /// F06 criterion 4, the clipping half: at 42, 46 and 49 mm, each at its default text size and at
        /// AX3, every watch component keeps inside the screen, and no text is cut.
        @Suite("WatchComponentLayout", .tags(.design))
        struct WatchComponentLayoutTests {
            /// The pages' inset, 12 pt: ink that reaches closer to an edge overflowed the screen.
            static let inset = Int(LedgerSpacing.m)

            static let galleries: [(name: String, view: AnyView)] = [
                ("WatchPrimaryButton", AnyView(WatchPrimaryButtonGallery())),
                ("WatchRestRing", AnyView(WatchRestRingGallery())),
                ("WatchStatBlock", AnyView(WatchStatBlockGallery()))
            ]

            static func render(_ view: some View, _ appearance: WatchAppearance) -> PixelBuffer? {
                RenderedImage.render(
                    view.ledgerWatchPage().frame(width: appearance.size.size.width),
                    dynamicTypeSize: appearance.dynamicTypeSize
                ).flatMap(PixelBuffer.init)
            }

            @Test(
                "Every watch gallery keeps its 12 pt inset: nothing reaches the screen's edge",
                arguments: WatchAppearance.matrix
            )
            func watchGalleries_everyCell_keepTheirInset(_ appearance: WatchAppearance) throws {
                for gallery in Self.galleries {
                    let pixels = try #require(Self.render(gallery.view, appearance), "\(gallery.name) did not render")
                    let margins = try #require(pixels.inkMargins(), "\(gallery.name) drew nothing")
                    #expect(pixels.width == Int(appearance.size.size.width))
                    #expect(
                        margins.smallest >= Self.inset - 1,
                        "\(gallery.name) at \(appearance): ink \(margins) px from the edges"
                    )
                }
            }

            @Test(
                "The rest ring fits the screen, inside its inset, with a five-character label",
                arguments: WatchAppearance.matrix
            )
            func watchRestRing_everyCell_fitsTheScreen(_ appearance: WatchAppearance) throws {
                let image = try #require(RenderedImage.render(
                    WatchRestRing(progress: 1, label: "10:00"),
                    dynamicTypeSize: appearance.dynamicTypeSize
                ))
                let screen = appearance.size.size
                #expect(CGFloat(image.width) <= screen.width - 2 * LedgerSpacing.m, "\(appearance): \(image.width) pt")
                #expect(
                    CGFloat(image.height) <= screen.height - 2 * LedgerSpacing.m,
                    "\(appearance): \(image.height) pt"
                )
            }

            /// Two views that differ only in their last character render differently unless that
            /// character is cut ("…"). At 42 mm and AX3, the narrowest screen at the largest text.
            @Test("No watch text is cut at 42 mm and AX3: the last character always shows")
            func watchText_narrowestLargest_isNeverCut() throws {
                let appearance = WatchAppearance(.mm42, .accessibility3)
                let pairs: [String: [AnyView]] = [
                    "button title": [button("Save workout and finish"), button("Save workout and finisk")],
                    "ring label": [ring("10:00"), ring("10:01")],
                    "stat value": [stats("24,180", "Lb moved"), stats("24,181", "Lb moved")],
                    "stat caption": [stats("24,180", "Lb moved"), stats("24,180", "Lb movee")]
                ]
                for (name, views) in pairs {
                    let renders = try views.map { try #require(Self.render($0, appearance)) }
                    #expect(renders[0] != renders[1], "\(name): the last character does not show")
                }
                // Positive control: a value far too long for a half-width column is cut, and the probe sees it.
                let long = try #require(Self.render(stats("1,002,002,002,002.5", "Sets"), appearance))
                let longer = try #require(Self.render(stats("1,002,002,002,002.6", "Sets"), appearance))
                #expect(long == longer, "the probe cannot see a cut")
            }

            private func button(_ title: String) -> AnyView {
                AnyView(WatchPrimaryButton(title) {})
            }

            private func ring(_ label: String) -> AnyView {
                AnyView(WatchRestRing(progress: 1, label: label))
            }

            /// Two blocks side by side, as the summary screen sets them.
            private func stats(_ value: String, _ caption: String) -> AnyView {
                AnyView(HStack(alignment: .top, spacing: LedgerSpacing.m) {
                    WatchStatBlock(value, caption: caption)
                    WatchStatBlock("142", caption: "Avg BPM")
                })
            }
        }
    }

    private extension PixelBuffer {
        /// How far, in pixels, the nearest ink is from each edge; ink is any pixel unlike the watch's
        /// black by more than 24 in a channel. Nil when there is no ink.
        func inkMargins() -> InkMargins? {
            let black = Pixel(hex: 0x000000)
            let rows = (0 ..< height).filter { row in
                (0 ..< width).contains { pixel(column: $0, row: row).differs(from: black, by: 24) }
            }
            guard let columns = inkedColumns(differingFrom: black), let top = rows.first, let bottom = rows.last else {
                return nil
            }
            return InkMargins(
                left: columns.lowerBound, right: width - 1 - columns.upperBound, top: top, bottom: height - 1 - bottom
            )
        }
    }

    private struct InkMargins: CustomStringConvertible {
        let left, right, top, bottom: Int

        var smallest: Int {
            min(left, right, top, bottom)
        }

        var description: String {
            "left \(left), right \(right), top \(top), bottom \(bottom)"
        }
    }
#endif
