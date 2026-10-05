#if DEBUG
    @testable import FeatureOnboarding
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F08 S2, criterion 10: the screen's states against their references, drawn from the preview registry's models at
    /// the iPhone 17 width and their own height. 18 images (plan ruling O10): steps 1 and 3 in the full phone matrix,
    /// light and dark at three text sizes; step 2 and the failure at the default size; the six-day list in dark at the
    /// default and the largest size. Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
    @Suite("Onboarding snapshots", .serialized)
    struct OnboardingSnapshotTests {
        private func screen(_ preview: OnboardingPreview) -> some View {
            preview.content.frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("Step 1, the goal, matches its references")
        func goal_matchesReferences() {
            assertLedgerSnapshot(of: screen(.goal), devices: [.phone])
        }

        @Test("Step 2, the days, matches its references")
        func days_matchesReferences() {
            assertLedgerSnapshot(of: screen(.days), devices: [.phone], typeSizes: [.large])
        }

        @Test("Step 3, the four-day program, matches its references")
        func program_matchesReferences() {
            assertLedgerSnapshot(of: screen(.program), devices: [.phone])
        }

        @Test("Step 3, the six-day program, matches its references")
        func programSixDays_matchesReferences() {
            assertLedgerSnapshot(
                of: screen(.programSixDays),
                devices: [.phone],
                themes: [.dark],
                typeSizes: [.large, .accessibility3]
            )
        }

        @Test("Step 3 after a failed save matches its references")
        func failed_matchesReferences() {
            assertLedgerSnapshot(of: screen(.failed), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
