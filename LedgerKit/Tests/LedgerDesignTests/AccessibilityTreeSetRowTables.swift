#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import UIKit

    /// `AccessibilityTreeTests`' set-row tables: `SetRow` in each state and each initializer form,
    /// `SetRowSteppers`, and the whole gallery in VoiceOver's order.
    extension TreeTables {
        nonisolated static let sets: [TreeCase] = [
            TreeCase("SetRow, pending", [.button("2, 185, 5", value: "Pending"), .button("Log set 2")]) {
                row(.pending, check: "Log set 2")
            },
            TreeCase("SetRow, active", [.button("2, 185, 5", value: "Current set"), .button("Log set 2")]) {
                row(.active, check: "Log set 2")
            },
            TreeCase(
                "SetRow, done",
                [.button("2, 185, 5", value: "Done"), .button("Undo set 2", value: "Done", .selected)]
            ) { row(.done, check: "Undo set 2") },
            // `accessibilitySummary`, in each form its initializers take (fix round 3, Pete's re-plan):
            // a literal and a `String` (the `String?` initializer), a `LocalizedStringKey`, a `Text`, and
            // an explicit `nil`. Each names the row and only the row. SwiftUI's `.accessibilityLabel` on
            // a `SetRow` reaches both elements; since the shadowing overload is gone, every call of it
            // is SwiftUI's modifier, which the `SetRow` doc forbids.
            TreeCase("SetRow, done, summary as a literal", named) {
                SetRow(
                    number: "2", weight: "185", reps: "5", state: .done, checkLabel: "Undo set 2",
                    accessibilitySummary: "Set 2, 185 pounds, 5 reps"
                ) {} onCheck: {}
            },
            TreeCase("SetRow, done, summary as a String", named) {
                let summary = String(localized: "Set 2, 185 pounds, 5 reps")
                return SetRow(
                    number: "2", weight: "185", reps: "5", state: .done, checkLabel: "Undo set 2",
                    accessibilitySummary: summary
                ) {} onCheck: {}
            },
            TreeCase("SetRow, done, summary as a LocalizedStringKey", named) {
                let key: LocalizedStringKey = "Set 2, 185 pounds, 5 reps"
                return SetRow(
                    number: "2", weight: "185", reps: "5", state: .done, checkLabel: "Undo set 2",
                    accessibilitySummary: key
                ) {} onCheck: {}
            },
            TreeCase("SetRow, done, summary as a Text", named) {
                SetRow(
                    number: "2", weight: "185", reps: "5", state: .done, checkLabel: "Undo set 2",
                    accessibilitySummary: Text(verbatim: "Set 2, 185 pounds, 5 reps")
                ) {} onCheck: {}
            },
            TreeCase(
                "SetRow, done, summary nil",
                [.button("2, 185, 5", value: "Done"), .button("Undo set 2", value: "Done", .selected)]
            ) {
                SetRow(
                    number: "2", weight: "185", reps: "5", state: .done, checkLabel: "Undo set 2",
                    accessibilitySummary: nil
                ) {} onCheck: {}
            },
            TreeCase("SetRow, pending, pressed", [.button("2, 185, 5", value: "Pending"), .button("Log set 2")]) {
                row(.pending, check: "Log set 2").environment(\.ledgerDrawsPressed, true)
            },
            TreeCase("SetRow, drop set", [.button("D, 155, 5", value: "Pending"), .button("Log drop set")]) {
                SetRow(
                    number: "D",
                    weight: "155",
                    reps: "5",
                    state: .pending,
                    checkLabel: "Log drop set"
                ) {} onCheck: {}
            },
            TreeCase("SetRowSteppers", steppers) { SetRowSteppersCase() },
            TreeCase("SetRowSteppers, pressed", steppers) {
                SetRowSteppersCase().environment(\.ledgerDrawsPressed, true)
            },
            TreeCase(
                "SetRowSteppers at accessibility3 (stacked)",
                at: SnapshotAppearance(.dark, .accessibility3),
                steppers
            ) {
                SetRowSteppersCase()
            },
            TreeCase("SetRow gallery, in order", gallery) { SetRowGallery() },
            TreeCase(
                "SetRow gallery at accessibility3, in order",
                at: SnapshotAppearance(.dark, .accessibility3),
                gallery
            ) {
                SetRowGallery()
            }
        ]

        /// A done row named "Set 2, 185 pounds, 5 reps": the row takes the name, the check keeps its own.
        nonisolated static let named: [TreeNode] = [
            .button("Set 2, 185 pounds, 5 reps", value: "Done"),
            .button("Undo set 2", value: "Done", .selected)
        ]

        nonisolated static let steppers: [TreeNode] = [
            .adjustable("5 lb", value: "185 pounds"),
            .adjustable("1 rep", value: "5 reps")
        ]

        /// `SetRowGallery`: the header, then each row and its check, with the steppers after the
        /// active row.
        nonisolated static let gallery: [TreeNode] = [
            .text("#, lb, reps"),
            .button("1, 185, 5", value: "Done"), .button("Undo set 1", value: "Done", .selected),
            .button("2, 185, 5", value: "Current set"), .button("Log set 2"),
            .adjustable("5 lb", value: "185 pounds"), .adjustable("1 rep", value: "5 reps"),
            .button("3, 102.5, 12", value: "Pending"), .button("Log set 3"),
            .button("D, 155, 5", value: "Pending"), .button("Log drop set")
        ]

        @MainActor static func row(_ state: SetRowState, check: String) -> SetRow {
            SetRow(number: "2", weight: "185", reps: "5", state: state, checkLabel: check) {} onCheck: {}
        }
    }

    private struct SetRowSteppersCase: View {
        var body: some View {
            SetRowSteppers(
                weightStep: "5 lb",
                repStep: "1 rep",
                weight: "185 pounds",
                reps: "5 reps",
                onWeight: { _ in },
                onReps: { _ in }
            )
        }
    }
#endif
