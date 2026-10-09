#if DEBUG
    @testable import FeatureWorkout
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F10 S4, criteria 1, 6 and 10: the cover's header against its references, as the plan lists them: light
    /// and dark at `.large` and `.xLarge`. It is the header at the iPhone 17 width and its own height
    /// (`WorkoutParts`), with time standing still at the state's moment, so the elapsed time is the same on
    /// every run: "24:22" after some minutes, and "1:01:05" past an hour, which has one reference of its own
    /// because no test can read a timer's text. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host
    /// draws none.
    @Suite("Workout snapshots", .serialized, .tags(.feature, .snapshot))
    struct WorkoutSnapshotTests {
        private func header(_ preview: WorkoutPreview) -> some View {
            WorkoutParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The header after some minutes matches its references")
        func header_matchesReferences() {
            assertLedgerSnapshot(of: header(.minutes), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("Past an hour the elapsed time reads 1:01:05")
        func header_pastAnHour_matchesReference() {
            assertLedgerSnapshot(of: header(.hour), devices: [.phone], themes: [.dark], typeSizes: [.large])
        }
    }
#endif
