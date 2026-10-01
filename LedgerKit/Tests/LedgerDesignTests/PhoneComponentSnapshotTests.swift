@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

// F06 criterion 3 for slice 3's phone components: each component's gallery (every state it has) in
// the phone matrix, light and dark × large, xLarge and accessibility3, at the iPhone 17 width.
// Recorded on the PR-plan simulator (iPhone 17, iOS 27.0, the pin in scripts/check.sh). One suite per
// component, as slice 2's `ComponentSnapshotTests`.
#if os(iOS)
    extension RenderingSuites {
        @Suite("WeekStripSnapshots", .tags(.design, .snapshot))
        struct WeekStripSnapshotTests {
            @Test("WeekStrip matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func weekStrip_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: WeekStripGallery().phonePage(), appearance)
            }
        }

        @Suite("StatTileSnapshots", .tags(.design, .snapshot))
        struct StatTileSnapshotTests {
            @Test("StatTile matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func statTile_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: StatTileGallery().phonePage(), appearance)
            }
        }

        @Suite("ProgressSegmentsSnapshots", .tags(.design, .snapshot))
        struct ProgressSegmentsSnapshotTests {
            @Test("ProgressSegments matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func progressSegments_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: ProgressSegmentsGallery().phonePage(), appearance)
            }
        }

        @Suite("SheetChromeSnapshots", .tags(.design, .snapshot))
        struct SheetChromeSnapshotTests {
            @Test("SheetChrome matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func sheetChrome_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: SheetChromeGallery().phonePage(), appearance)
            }
        }

        @Suite("EmptyStateSnapshots", .tags(.design, .snapshot))
        struct EmptyStateSnapshotTests {
            @Test("EmptyState matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func emptyState_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: EmptyStateGallery().phonePage(), appearance)
            }
        }

        /// Slice 3's phone components on one sheet, at the settings the matrix leaves out, as slice 2's
        /// `ComponentSheetSnapshotTests`: the largest text size, Bold Text, every button pressed (the
        /// sheet's cancel and the empty state's action), and Increase Contrast, which steps up every
        /// muted label, rule and track here.
        @Suite("PhoneComponentSheetSnapshots", .tags(.design, .snapshot))
        struct PhoneComponentSheetSnapshotTests {
            @Test("Slice 3's phone components at accessibility5 match their reference (dark)")
            func slice3Components_accessibility5_matchesReference() {
                assertPhoneSnapshot(of: Slice3Components().phonePage(), SnapshotAppearance(.dark, .accessibility5))
            }

            @Test("Slice 3's phone components with Bold Text match their reference (dark, large)")
            func slice3Components_boldText_matchesReference() {
                let appearance = SnapshotAppearance(.dark, .large)
                assertPhoneSnapshot(
                    of: Slice3Components().phonePage().environment(\.legibilityWeight, .bold),
                    appearance,
                    named: "bold-\(appearance)"
                )
            }

            @Test(
                "SheetChrome and EmptyState, pressed, match their references (large)",
                arguments: [ColorScheme.light, .dark]
            )
            func pressableComponents_pressed_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                let sheet = VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                    SheetChromeGallery()
                    EmptyStateGallery()
                }
                assertPhoneSnapshot(
                    of: sheet.phonePage().environment(\.ledgerDrawsPressed, true),
                    appearance,
                    named: "pressed-\(appearance)"
                )
            }

            @Test(
                "Slice 3's phone components with Increase Contrast match their references (large)",
                arguments: [ColorScheme.light, .dark]
            )
            func slice3Components_increasedContrast_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                assertPhoneSnapshot(
                    of: Slice3Components().phonePage(),
                    appearance,
                    named: "increasedContrast-\(appearance)",
                    modifyingTraits: { $0.accessibilityContrast = .high }
                )
            }
        }
    }

    /// Slice 3's phone galleries, one after another.
    private struct Slice3Components: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                WeekStripGallery()
                StatTileGallery()
                ProgressSegmentsGallery()
                SheetChromeGallery()
                EmptyStateGallery()
            }
        }
    }
#endif
