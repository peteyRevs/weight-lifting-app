#if DEBUG
    @testable import FeatureWorkout
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// The cover against its references, at the iPhone 17 width and its own height (`WorkoutParts`: the
    /// header over the page, without the scroll view), with time standing still at the state's moment.
    /// Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
    ///
    /// - F10 S4, criteria 1, 6 and 10: the header alone, light and dark at `.large` and `.xLarge`: "24:22"
    ///   after some minutes, and "1:01:05" past an hour, which has one reference of its own because no test
    ///   can read a timer's text.
    /// - F10 S5, criteria 1, 2 and 10, as the plan lists them: the whole cover in three states (a set being
    ///   logged, with a last workout and "Repeat"; a drop set in kilograms with nothing remaining; no
    ///   history) light and dark, the logging state at `.xLarge`, one dark `.accessibility3`, and one with
    ///   Increase Contrast.
    @Suite("Workout snapshots", .serialized, .tags(.feature, .snapshot))
    struct WorkoutSnapshotTests {
        private func header(_ preview: WorkoutPreview) -> some View {
            WorkoutParts(preview: preview, headerOnly: true).frame(width: SnapshotConfig.phoneWidth)
        }

        private func cover(_ preview: WorkoutPreview) -> some View {
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

        @Test("Logging a set: two rows logged, the shown row with its steppers, Last with Repeat, and what remains")
        func cover_logging_matchesReferences() {
            assertLedgerSnapshot(of: cover(.logging), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("Logging a set at the largest text size of the matrix")
        func cover_logging_accessibility3_matchesReference() {
            assertLedgerSnapshot(of: cover(.logging), devices: [.phone], themes: [.dark], typeSizes: [.accessibility3])
        }

        @Test("A drop set, in kilograms, on the last exercise: nothing remains")
        func cover_dropSet_matchesReferences() {
            assertLedgerSnapshot(of: cover(.dropSet), devices: [.phone], typeSizes: [.large])
        }

        #if os(iOS)
            @Test("With Increase Contrast the page keeps its layout and takes the stronger inks and rules")
            func cover_logging_increasedContrast_matchesReference() {
                assertPhoneSnapshot(
                    of: cover(.logging),
                    SnapshotAppearance(.light, .large),
                    named: "light-large-increasedContrast",
                    modifyingTraits: { $0.accessibilityContrast = .high }
                )
            }
        #endif

        @Test("No history yet: no Repeat")
        func cover_noHistory_matchesReferences() {
            assertLedgerSnapshot(of: cover(.started), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
