#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S2 adversarial (G2): a past workout's detail laid out right to left. VoiceOver reads the same stops in the
    /// same order as left to right, and the day, the name and "Delete workout" (flush with the leading edge) stand
    /// mirrored: on the right, as far in from it as they stand from the left in English. At `.accessibility5` with
    /// Bold Text too, and in the unreadable state.
    @Suite("Adversarial F13 S2 · the detail right to left", .serialized, .tags(.feature))
    struct WorkoutDetailMirrorAdversarialTests {
        static func placed(_ preview: DetailPreview, rightToLeft: Bool, size: DynamicTypeSize) -> [PlacedStop] {
            DetailParts(preview: preview)
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                .environment(\.legibilityWeight, size.isAccessibilitySize ? .bold : .regular)
                .placedStops(SnapshotAppearance(.light, size))
        }

        @Test(
            "Right to left, the stops and their order are the same, and the leading parts are mirrored",
            arguments: [DetailPreview.withRecords, .unreadable], [DynamicTypeSize.large, .accessibility5]
        )
        func rightToLeft_mirrorsAndKeepsTheOrder(_ preview: DetailPreview, _ size: DynamicTypeSize) throws {
            let leftToRight = Self.placed(preview, rightToLeft: false, size: size)
            let rightToLeft = Self.placed(preview, rightToLeft: true, size: size)
            try #require(!leftToRight.isEmpty)
            let sameStops = leftToRight.map(\.stop) == rightToLeft.map(\.stop)
            #expect(sameStops, "\(preview.rawValue) at \(size)")
            let width = SnapshotConfig.phoneWidth
            let title = (try? preview.model())?.title
            let leading = ["Delete workout", "This workout can't be read."] + (title.map { [$0] } ?? [])
            for (left, right) in zip(leftToRight, rightToLeft) where leading.contains(left.stop.label) {
                let mirrored = abs(right.frame.maxX - (width - left.frame.minX)) < 1
                #expect(mirrored, "\(left.stop.label): \(left.frame) left to right, \(right.frame) right to left")
            }
        }
    }
#endif
