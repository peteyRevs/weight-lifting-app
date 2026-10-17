#if DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F11 S9, criterion 5: the builder's and the exercise library's states against their references. Each is
    /// the state's parts (`ProgramParts`) at the iPhone 17 width and their own height: a screen puts its page in
    /// a scroll view, which has no height of its own (testing-strategy §2.6). The states are the preview
    /// registry's.
    ///
    /// Each screen's main state is drawn in the phone matrix, light and dark at `.large`, `.xLarge` and
    /// `.accessibility3`; the other states in light and dark at the default size. Criterion 7's settings are
    /// drawn once each, dark: sixteen weeks under a long name at the default size and at `.accessibility3`,
    /// and both screens right to left and under Increase Contrast. Recorded on the PR plan's iPhone 17 (iOS 27.0); the
    /// Mac host draws none.
    @Suite("Program snapshots", .serialized, .tags(.feature, .snapshot))
    struct ProgramSnapshotTests {
        private func parts(_ preview: ProgramPreview) -> some View {
            ProgramParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The builder matches its references")
        func builder_matchesReferences() {
            assertLedgerSnapshot(of: parts(.builder), devices: [.phone])
        }

        @Test("The builder with the deload week selected matches its references")
        func deloadWeek_matchesReferences() {
            assertLedgerSnapshot(of: parts(.deloadWeek), devices: [.phone], typeSizes: [.large])
        }

        @Test("The builder with a day that has no exercise matches its references")
        func emptyDay_matchesReferences() {
            assertLedgerSnapshot(of: parts(.emptyDay), devices: [.phone], typeSizes: [.large])
        }

        @Test("The builder with the two-weeks message matches its references")
        func twoWeeks_matchesReferences() {
            assertLedgerSnapshot(of: parts(.twoWeeks), devices: [.phone], typeSizes: [.large])
        }

        @Test("Sixteen weeks under a long name match their references, at the default and an accessibility size")
        func sixteenWeeks_matchesReferences() {
            assertLedgerSnapshot(
                of: parts(.sixteenWeeks), devices: [.phone], themes: [.dark], typeSizes: [.large, .accessibility3]
            )
        }

        @Test("The exercise library matches its references")
        func library_matchesReferences() {
            assertLedgerSnapshot(of: parts(.library), devices: [.phone])
        }

        @Test("The exercise library with three exercises picked matches its references")
        func libraryPicked_matchesReferences() {
            assertLedgerSnapshot(of: parts(.libraryPicked), devices: [.phone], typeSizes: [.large])
        }

        @Test("The exercise library with nothing that matches the filter matches its references")
        func libraryNothing_matchesReferences() {
            assertLedgerSnapshot(of: parts(.libraryNothing), devices: [.phone], typeSizes: [.large])
        }

        @Test("Right to left, both screens match their references")
        func rightToLeft_matchesReferences() {
            for preview in [ProgramPreview.builder, .libraryPicked] {
                assertLedgerSnapshot(
                    of: parts(preview).environment(\.layoutDirection, .rightToLeft),
                    named: preview == .builder ? "builder" : "library",
                    devices: [.phone], themes: [.dark], typeSizes: [.large]
                )
            }
        }

        #if os(iOS)
            @Test("Under Increase Contrast, both screens match their references")
            func increaseContrast_matchesReferences() {
                for preview in [ProgramPreview.builder, .libraryPicked] {
                    assertPhoneSnapshot(
                        of: parts(preview), SnapshotAppearance(.dark, .large),
                        named: preview == .builder ? "builder" : "library"
                    ) { $0.accessibilityContrast = .high }
                }
            }
        #endif
    }
#endif
