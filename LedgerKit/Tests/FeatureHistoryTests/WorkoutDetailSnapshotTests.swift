#if DEBUG
    @testable import FeatureHistory
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F13 S2: a past workout's detail against its references. Each is the state's parts (`DetailParts`) at the iPhone
    /// 17 width and their own height: the screen puts its page in a scroll view, which has no height of its own
    /// (testing-strategy §2.6). The states are the preview registry's.
    ///
    /// With records, without and in kilograms, in light and dark at the default size, and with records at
    /// `.accessibility3` too: eight references. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws
    /// none.
    @Suite("Workout detail snapshots", .serialized, .tags(.feature, .snapshot))
    struct WorkoutDetailSnapshotTests {
        private func parts(_ preview: DetailPreview) -> some View {
            DetailParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The detail with records matches its references, at the default and an accessibility size")
        func withRecords_matchesReferences() {
            assertLedgerSnapshot(of: parts(.withRecords), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("The detail without records matches its references")
        func noRecords_matchesReferences() {
            assertLedgerSnapshot(of: parts(.noRecords), devices: [.phone], typeSizes: [.large])
        }

        @Test("7. The detail in kilograms matches its references")
        func kilograms_matchesReferences() {
            assertLedgerSnapshot(of: parts(.kilograms), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
