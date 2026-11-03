#if DEBUG
    @testable import FeatureHistory
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F13 S3: the edit sheet against its references. Unchanged, changed and failed, light and dark at the default
    /// size, and changed at `.accessibility3` in light and dark too: eight references (the plan's seven, plus dark at
    /// `.accessibility3`, as `assertLedgerSnapshot` draws both themes).
    @Suite("Edit sets snapshots", .serialized, .tags(.feature, .snapshot))
    struct EditSetsSnapshotTests {
        private func parts(_ preview: EditPreview) -> some View {
            EditParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The sheet, unchanged, matches its references")
        func unchanged_matchesReferences() {
            assertLedgerSnapshot(of: parts(.unchanged), devices: [.phone], typeSizes: [.large])
        }

        @Test("The sheet, changed, matches its references, at the default and an accessibility size")
        func changed_matchesReferences() {
            assertLedgerSnapshot(of: parts(.changed), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("The sheet with a failed save matches its references")
        func failed_matchesReferences() {
            assertLedgerSnapshot(of: parts(.failed), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
