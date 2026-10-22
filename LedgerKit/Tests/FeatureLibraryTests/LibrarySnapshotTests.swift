#if DEBUG
    @testable import FeatureLibrary
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S1: the Library's states against their references. Each is the state's parts (`LibraryParts`) at the
    /// iPhone 17 width and their own height: the screen puts its page in a scroll view, which has no height of its
    /// own (testing-strategy §2.6). The states are the preview registry's.
    ///
    /// Every state in light and dark at the default size, and the populated Library at `.accessibility3` too:
    /// twelve references. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
    @Suite("Library snapshots", .serialized, .tags(.feature, .snapshot))
    struct LibrarySnapshotTests {
        private func parts(_ preview: LibraryPreview) -> some View {
            LibraryParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The populated Library matches its references, at the default and an accessibility size")
        func populated_matchesReferences() {
            assertLedgerSnapshot(of: parts(.populated), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("The Library filtered to row, Back and Machine matches its references")
        func filtered_matchesReferences() {
            assertLedgerSnapshot(of: parts(.filtered), devices: [.phone], typeSizes: [.large])
        }

        @Test("The Library with nothing that matches the filter matches its references")
        func emptySearch_matchesReferences() {
            assertLedgerSnapshot(of: parts(.emptySearch), devices: [.phone], typeSizes: [.large])
        }

        @Test("The Library with no history matches its references")
        func noHistory_matchesReferences() {
            assertLedgerSnapshot(of: parts(.noHistory), devices: [.phone], typeSizes: [.large])
        }

        @Test("The Library with no exercise at all matches its references")
        func noExercises_matchesReferences() {
            assertLedgerSnapshot(of: parts(.noExercises), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
