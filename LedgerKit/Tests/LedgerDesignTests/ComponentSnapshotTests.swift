@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

// F06 criterion 3 for the slice-2 components: each component's gallery (every state it has) in
// the phone matrix, light and dark × large, xLarge and accessibility3, at the iPhone 17 width.
// Recorded on the PR-plan simulator (iPhone 17, iOS 27.0, the pin in scripts/check.sh). One suite per component.
#if os(iOS)
    extension RenderingSuites {
        @Suite("PrimaryButtonSnapshots", .tags(.design, .snapshot))
        struct PrimaryButtonSnapshotTests {
            @Test("PrimaryButton matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func primaryButton_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: PrimaryButtonGallery().phonePage(), appearance)
            }
        }

        @Suite("PillButtonSnapshots", .tags(.design, .snapshot))
        struct PillButtonSnapshotTests {
            @Test("PillButton matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func pillButton_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: PillButtonGallery().phonePage(), appearance)
            }
        }

        @Suite("IconPillButtonSnapshots", .tags(.design, .snapshot))
        struct IconPillButtonSnapshotTests {
            @Test("IconPillButton matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func iconPillButton_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: IconPillButtonGallery().phonePage(), appearance)
            }
        }

        /// F12 S1 (review m3): the two components moved from FeatureProgram: the search field empty and with a
        /// query, and a chip row with one chip selected.
        @Suite("FilterChipRowSnapshots", .tags(.design, .snapshot))
        struct FilterChipRowSnapshotTests {
            @Test("FilterChipRow and SearchField match their references", arguments: SnapshotAppearance.phoneMatrix)
            func filterChipRowAndSearchField_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: FilterChipRowGallery().phonePage(), appearance)
            }
        }

        @Suite("EyebrowSnapshots", .tags(.design, .snapshot))
        struct EyebrowSnapshotTests {
            @Test("Eyebrow matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func eyebrow_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: EyebrowGallery().phonePage(), appearance)
            }
        }

        @Suite("HairlineListSnapshots", .tags(.design, .snapshot))
        struct HairlineListSnapshotTests {
            @Test("HairlineList and HairlineRow match their references", arguments: SnapshotAppearance.phoneMatrix)
            func hairlineList_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: HairlineListGallery().phonePage(), appearance)
            }
        }

        @Suite("SetRowSnapshots", .tags(.design, .snapshot))
        struct SetRowSnapshotTests {
            @Test("SetRow and SetRowSteppers match their references", arguments: SnapshotAppearance.phoneMatrix)
            func setRow_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: SetRowGallery().phonePage(), appearance)
            }
        }

        @Suite("RestRingSnapshots", .tags(.design, .snapshot))
        struct RestRingSnapshotTests {
            @Test("RestRing matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func restRing_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: RestRingGallery().phonePage(), appearance)
            }
        }

        /// F10 S7b: the receipt's layout in the phone matrix: three tiles side by side, then one per row at
        /// accessibility3; a record, three rows, one with nothing logged.
        @Suite("ReceiptLayoutSnapshots", .tags(.design, .snapshot))
        struct ReceiptLayoutSnapshotTests {
            @Test("ReceiptLayout matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func receiptLayout_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: ReceiptLayoutGallery().phonePage(), appearance)
            }
        }

        /// The form controls of F11 S8, each gallery in the phone matrix, and the three on one sheet at the
        /// settings the matrix leaves out (Increase Contrast in both themes, pressed, accessibility5).
        @Suite("FormControlSnapshots", .tags(.design, .snapshot))
        struct FormControlSnapshotTests {
            @Test("StepperField matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func stepperField_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: StepperFieldGallery().phonePage(), appearance)
            }

            @Test("LedgerToggleStyle matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func ledgerToggleStyle_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: LedgerToggleGallery().phonePage(), appearance)
            }

            @Test("WrapLayout matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func wrapLayout_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: WrapLayoutGallery().phonePage(), appearance)
            }

            @Test("WrapLayout, right to left, matches its reference (dark, large)")
            func wrapLayout_rightToLeft_matchesReference() {
                let appearance = SnapshotAppearance(.dark, .large)
                assertPhoneSnapshot(
                    of: WrapLayoutGallery().phonePage().environment(\.layoutDirection, .rightToLeft),
                    appearance,
                    named: "rightToLeft-\(appearance)"
                )
            }

            @Test(
                "The form controls with Increase Contrast match their references (large)",
                arguments: [ColorScheme.light, .dark]
            )
            func formControls_increasedContrast_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                assertPhoneSnapshot(
                    of: FormControls().phonePage(),
                    appearance,
                    named: "increasedContrast-\(appearance)",
                    modifyingTraits: { $0.accessibilityContrast = .high }
                )
            }

            @Test("The form controls, pressed, match their reference (dark, large)")
            func formControls_pressed_matchesReference() {
                let appearance = SnapshotAppearance(.dark, .large)
                assertPhoneSnapshot(
                    of: FormControls().phonePage().environment(\.ledgerDrawsPressed, true),
                    appearance,
                    named: "pressed-\(appearance)"
                )
            }

            @Test("The form controls at accessibility5 match their reference (light)")
            func formControls_accessibility5_matchesReference() {
                assertPhoneSnapshot(of: FormControls().phonePage(), SnapshotAppearance(.light, .accessibility5))
            }
        }

        /// Every slice-2 component on one sheet, at the settings the matrix leaves out: the largest
        /// text size (the components claim to hold up through AX5 without clipping), Bold Text (they
        /// follow it), every button pressed, and Increase Contrast, whose stronger hairlines and inks
        /// are every rule, outline, ring track and muted label (fix round 1, S2-5). Plus the set row,
        /// the densest component, in light at AX5. A few targeted images, not the full cross product.
        @Suite("ComponentSheetSnapshots", .tags(.design, .snapshot))
        struct ComponentSheetSnapshotTests {
            @Test("Every component at accessibility5 matches its reference (dark)")
            func allComponents_accessibility5_matchesReference() {
                assertPhoneSnapshot(of: AllComponents().phonePage(), SnapshotAppearance(.dark, .accessibility5))
            }

            @Test("Every component, pressed, matches its references (large)", arguments: [ColorScheme.light, .dark])
            func allComponents_pressed_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                assertPhoneSnapshot(
                    of: AllComponents().phonePage().environment(\.ledgerDrawsPressed, true),
                    appearance,
                    named: "pressed-\(appearance)"
                )
            }

            @Test(
                "Every component with Increase Contrast matches its references (large)",
                arguments: [ColorScheme.light, .dark]
            )
            func allComponents_increasedContrast_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                assertPhoneSnapshot(
                    of: AllComponents().phonePage(),
                    appearance,
                    named: "increasedContrast-\(appearance)",
                    modifyingTraits: { $0.accessibilityContrast = .high }
                )
            }

            @Test("SetRow and its steppers match their reference at accessibility5 (light)")
            func setRow_lightAccessibility5_matchesReference() {
                assertPhoneSnapshot(of: SetRowGallery().phonePage(), SnapshotAppearance(.light, .accessibility5))
            }

            @Test("Every component with Bold Text matches its reference (dark, large)")
            func allComponents_boldText_matchesReference() {
                let appearance = SnapshotAppearance(.dark, .large)
                assertPhoneSnapshot(
                    of: AllComponents().phonePage().environment(\.legibilityWeight, .bold),
                    appearance,
                    named: "bold-\(appearance)"
                )
            }
        }
    }

    /// The slice-2 galleries, one after another.
    private struct AllComponents: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                PrimaryButtonGallery()
                PillButtonGallery()
                IconPillButtonGallery()
                EyebrowGallery()
                HairlineListGallery()
                SetRowGallery()
                RestRingGallery()
            }
        }
    }

    /// The form controls' galleries, one after another.
    private struct FormControls: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                StepperFieldGallery()
                LedgerToggleGallery()
                WrapLayoutGallery()
            }
        }
    }

    extension View {
        /// A gallery as the phone shows it: screen inset, on the ground, 402 pt wide. Every phone
        /// component suite uses it (slice 3's too).
        func phonePage() -> some View {
            ledgerGalleryPage().frame(width: SnapshotConfig.phoneWidth)
        }
    }
#endif
