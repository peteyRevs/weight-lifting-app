#if DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F11 S10, criterion 9: the Day editor's states against their references. Each is the state's parts
    /// (`ProgramParts`: the pinned header over the page) at the iPhone 17 width and their own height, since
    /// the screen puts its page in a scroll view, which has no height of its own (testing-strategy §2.6). The
    /// states are the preview registry's.
    ///
    /// Every exercise closed and an exercise open under a linear progression are drawn in the phone matrix,
    /// light and dark at `.large`, `.xLarge` and `.accessibility3`; the other states in light and dark at the
    /// default size. Criterion 11's settings are drawn once each, dark: long names at the default size and at
    /// `.accessibility3`, and the open exercise right to left and under Increase Contrast. Recorded on the PR
    /// plan's iPhone 17 (iOS 27.0); the Mac host draws none.
    @Suite("Day editor snapshots", .serialized, .tags(.feature, .snapshot))
    struct DayEditorSnapshotTests {
        private func parts(_ preview: ProgramPreview) -> some View {
            ProgramParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The Day editor with every exercise closed matches its references")
        func closed_matchesReferences() {
            assertLedgerSnapshot(of: parts(.dayEditor), devices: [.phone])
        }

        @Test("A day with a superset, its second exercise open, matches its references")
        func superset_matchesReferences() {
            assertLedgerSnapshot(of: parts(.daySuperset), devices: [.phone], typeSizes: [.large])
        }

        @Test("An exercise open under a linear progression matches its references")
        func openLinear_matchesReferences() {
            assertLedgerSnapshot(of: parts(.dayOpenLinear), devices: [.phone])
        }

        @Test("An exercise open under a double progression matches its references")
        func openDouble_matchesReferences() {
            assertLedgerSnapshot(of: parts(.dayOpenDouble), devices: [.phone], typeSizes: [.large])
        }

        @Test("An exercise with its drop set on matches its references")
        func dropSet_matchesReferences() {
            assertLedgerSnapshot(of: parts(.dayDropSet), devices: [.phone], typeSizes: [.large])
        }

        @Test("The deload week, an exercise open, matches its references")
        func deloadWeek_matchesReferences() {
            assertLedgerSnapshot(of: parts(.dayDeload), devices: [.phone], typeSizes: [.large])
        }

        @Test("Long day and exercise names match their references, at the default and an accessibility size")
        func longNames_matchesReferences() {
            assertLedgerSnapshot(
                of: parts(.dayLongNames), devices: [.phone], themes: [.dark], typeSizes: [.large, .accessibility3]
            )
        }

        @Test("Right to left, the open exercise matches its reference")
        func rightToLeft_matchesReferences() {
            assertLedgerSnapshot(
                of: parts(.dayOpenLinear).environment(\.layoutDirection, .rightToLeft),
                devices: [.phone], themes: [.dark], typeSizes: [.large]
            )
        }

        #if os(iOS)
            @Test("Under Increase Contrast, the open exercise matches its reference")
            func increaseContrast_matchesReferences() {
                assertPhoneSnapshot(of: parts(.dayOpenLinear), SnapshotAppearance(.dark, .large)) {
                    $0.accessibilityContrast = .high
                }
            }
        #endif
    }
#endif
