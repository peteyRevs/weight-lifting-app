#if DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S3: the exercise sheet's parts (`CreateParts`) against their references, at the iPhone 17 width and their
    /// own height: empty, filled in and with a taken name, in light and dark at the default size, and filled in at
    /// `.accessibility3` in dark: seven references. F15 S2b adds the name field alone at `.accessibility5` with a name
    /// of several lines, light: the guard of `AuditProgramLibrary.wholeName`, that the field's own text stays unseen
    /// under the name drawn whole.
    @Suite("Exercise sheet snapshots", .serialized, .tags(.feature, .snapshot))
    struct CreateExerciseSnapshotTests {
        private func parts(_ preview: CreatePreview) -> some View {
            CreateParts(preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The empty sheet matches its references")
        func empty_matchesReferences() {
            assertLedgerSnapshot(of: parts(.empty), devices: [.phone], typeSizes: [.large])
        }

        @Test("The filled-in sheet matches its references, at the default size and at an accessibility size")
        func filled_matchesReferences() {
            assertLedgerSnapshot(of: parts(.filled), devices: [.phone], typeSizes: [.large])
            assertLedgerSnapshot(
                of: parts(.filled),
                named: "filledAccessibility3",
                devices: [.phone],
                themes: [.dark],
                typeSizes: [.accessibility3]
            )
        }

        @Test("At Accessibility 5 a long name is drawn whole under the field, its own line unseen")
        func longName_accessibility5_matchesReference() {
            let field = CreateExerciseNameField(
                model: .init(label: "Name", text: "Landmine Squeeze Press with a Three-Second Pause", problem: nil)
            ) { _ in }
            let page = field.padding(LedgerSpacing.xl).frame(width: SnapshotConfig.phoneWidth)
            assertLedgerSnapshot(
                of: page.background(LedgerColor.ground),
                devices: [.phone],
                themes: [.light],
                typeSizes: [.accessibility5]
            )
        }

        @Test("The sheet with a taken name matches its references")
        func nameTaken_matchesReferences() {
            assertLedgerSnapshot(of: parts(.nameTaken), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
