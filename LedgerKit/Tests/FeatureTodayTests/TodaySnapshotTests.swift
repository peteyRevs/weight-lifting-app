#if DEBUG
    @testable import FeatureToday
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F09 S4, criterion 3: Today's states against their references. Each is the state's page (`TodayParts`) at
    /// the iPhone 17 width and its own height: the screen puts the page in a scroll view, which has no height of
    /// its own (testing-strategy §2.6). The states are the preview registry's.
    ///
    /// The six loaded states and the failed one are drawn in the phone matrix, light and dark at `.large`,
    /// `.xLarge` and `.accessibility3`; the sheet too. The two states that carry an open product question are
    /// drawn at the default size. Loading, which draws nothing, is the screen itself at an iPhone 17's size. One
    /// state, the live workout, is also drawn at `.accessibility5`, the largest text size there is. The resume
    /// time stands still at each state's moment. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host
    /// draws none.
    @Suite("Today snapshots", .serialized, .tags(.feature, .snapshot))
    struct TodaySnapshotTests {
        private func page(_ preview: TodayPreview) -> some View {
            TodayParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("Up next matches its references")
        func upNext_matchesReferences() {
            assertLedgerSnapshot(of: page(.upNext), devices: [.phone])
        }

        @Test("A live workout, its time standing still, matches its references")
        func resume_matchesReferences() {
            assertLedgerSnapshot(of: page(.resume), devices: [.phone])
        }

        @Test("A live workout at the largest accessibility text size matches its reference")
        func resume_largestTextSize_matchesReference() {
            assertLedgerSnapshot(of: page(.resume), devices: [.phone], themes: [.dark], typeSizes: [.accessibility5])
        }

        @Test("Logged matches its references")
        func logged_matchesReferences() {
            assertLedgerSnapshot(of: page(.logged), devices: [.phone])
        }

        @Test("A rest day matches its references")
        func restDay_matchesReferences() {
            assertLedgerSnapshot(of: page(.restDay), devices: [.phone])
        }

        @Test("The off-schedule sheet matches its references")
        func offSchedule_matchesReferences() throws {
            let sheet = try OffScheduleParts.ofTheRestDay().frame(width: SnapshotConfig.phoneWidth)
            assertLedgerSnapshot(of: sheet, devices: [.phone])
        }

        @Test("No program, with no workout yet, matches its references")
        func noProgram_matchesReferences() {
            assertLedgerSnapshot(of: page(.noProgram), devices: [.phone])
        }

        @Test("Block complete matches its references")
        func blockComplete_matchesReferences() {
            assertLedgerSnapshot(of: page(.blockComplete), devices: [.phone])
        }

        @Test("Loading draws the ground and nothing else")
        func loading_matchesReferences() {
            let screen = TodayScreen(state: .loading) { _ in }.frame(width: SnapshotConfig.phoneWidth, height: 874)
            assertLedgerSnapshot(of: screen, devices: [.phone], typeSizes: [.large])
        }

        @Test("Failed matches its references")
        func failed_matchesReferences() {
            assertLedgerSnapshot(of: page(.failed), devices: [.phone])
        }

        @Test("A workout live on a rest day matches its references")
        func resumeOnRestDay_matchesReferences() {
            assertLedgerSnapshot(of: page(.resumeOnRestDay), devices: [.phone], typeSizes: [.large])
        }

        @Test("A Monday on which nothing has moved yet matches its references")
        func mondayVolume_matchesReferences() {
            assertLedgerSnapshot(of: page(.mondayVolume), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
