#if DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S2: each history preview's page against its references, at the iPhone 17 width and its own height, in
    /// light and dark at the default size, and the logged history at `.accessibility3` too: ten references.
    @Suite("Exercise history snapshots", .serialized, .tags(.feature, .snapshot))
    struct ExerciseHistorySnapshotTests {
        private func parts(_ preview: HistoryPreview) -> some View {
            HistoryParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("A logged history matches its references, at the default and an accessibility size")
        func logged_matchesReferences() {
            assertLedgerSnapshot(of: parts(.logged), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("A history with two weeks off matches its references")
        func gaps_matchesReferences() {
            assertLedgerSnapshot(of: parts(.gaps), devices: [.phone], typeSizes: [.large])
        }

        @Test("A history never logged matches its references")
        func noData_matchesReferences() {
            assertLedgerSnapshot(of: parts(.noData), devices: [.phone], typeSizes: [.large])
        }

        @Test("A history in kilograms matches its references")
        func kilograms_matchesReferences() {
            assertLedgerSnapshot(of: parts(.kilograms), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
