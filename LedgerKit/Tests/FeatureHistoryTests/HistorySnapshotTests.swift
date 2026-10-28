#if DEBUG
    @testable import FeatureHistory
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F13 S1: the History list's states against their references. Each is the state's parts (`HistoryParts`) at the
    /// iPhone 17 width and their own height: the screen puts its page in a scroll view, which has no height of its own
    /// (testing-strategy §2.6). The states are the preview registry's.
    ///
    /// The populated and the empty list in light and dark at the default size, and the populated list at
    /// `.accessibility3` too: six references. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
    @Suite("History snapshots", .serialized, .tags(.feature, .snapshot))
    struct HistorySnapshotTests {
        private func parts(_ preview: HistoryPreview) -> some View {
            HistoryParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The populated list matches its references, at the default and an accessibility size")
        func populated_matchesReferences() {
            assertLedgerSnapshot(of: parts(.populated), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("The empty list matches its references")
        func empty_matchesReferences() {
            assertLedgerSnapshot(of: parts(.empty), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
