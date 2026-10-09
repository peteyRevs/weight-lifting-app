#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import UIKit

    /// `AccessibilityTreeTests`' tables for the form controls (F11 S8): `StepperField` in every state,
    /// `.toggleStyle(.ledger)` on and off, and `WrapLayout` with pill buttons inside it.
    extension TreeTables {
        nonisolated static let forms: [TreeCase] = stepperFields + toggles + wraps

        nonisolated static let stepperFields: [TreeCase] = [
            TreeCase("StepperField, both steps on", [.adjustable("Sets", value: "5")]) {
                StepperField("Sets", value: "5", onDecrement: {}, onIncrement: {})
            },
            TreeCase("StepperField, a spoken value", [.adjustable("Rest", value: "2 minutes 30 seconds")]) {
                StepperField(
                    "Rest", value: "2:30", spokenValue: "2 minutes 30 seconds", onDecrement: {}, onIncrement: {}
                )
            },
            TreeCase("StepperField, at its lowest (no −)", [.adjustable("Sets", value: "1")]) {
                StepperField("Sets", value: "1", onDecrement: nil, onIncrement: {})
            },
            TreeCase("StepperField, at its highest (no +)", [.adjustable("Target RPE", value: "10")]) {
                StepperField("Target RPE", value: "10", onDecrement: {}, onIncrement: nil)
            },
            TreeCase("StepperField, both steps off: dimmed", [dimmed("Sets", value: "5")]) {
                StepperField("Sets", value: "5", onDecrement: nil, onIncrement: nil)
            },
            TreeCase("StepperField, disabled: dimmed", [dimmed("Top of range", value: "12")]) {
                StepperField("Top of range", value: "12", onDecrement: {}, onIncrement: {}).disabled(true)
            },
            TreeCase(
                "StepperField, stacked at accessibility3",
                at: SnapshotAppearance(.dark, .accessibility3),
                [.adjustable("Sets", value: "5")]
            ) {
                StepperField("Sets", value: "5", onDecrement: {}, onIncrement: {})
            },
            TreeCase(
                "StepperField gallery: the rules between the fields are no stops",
                [
                    .adjustable("Sets", value: "5"), .adjustable("Rest", value: "30 seconds"),
                    .adjustable("Target RPE", value: "10"),
                    .adjustable("Start load for the first week", value: "1,022.5 lb"),
                    dimmed("Top of range", value: "12")
                ]
            ) { StepperFieldGallery() }
        ]

        nonisolated static let toggles: [TreeCase] = [
            TreeCase("LedgerToggleStyle, off", [toggle("Drop set", isOn: false)]) { dropSet(false) },
            TreeCase("LedgerToggleStyle, on", [toggle("Drop set", isOn: true)]) { dropSet(true) },
            TreeCase("LedgerToggleStyle, on, disabled", [toggle("Drop set", isOn: true, .notEnabled)]) {
                dropSet(true).disabled(true)
            },
            TreeCase(
                "LedgerToggleStyle, on, at accessibility3",
                at: SnapshotAppearance(.dark, .accessibility3),
                [toggle("Drop set", isOn: true)]
            ) { dropSet(true) },
            TreeCase(
                "LedgerToggleStyle gallery: a label of two texts is one stop",
                [
                    toggle("Drop set", isOn: false), toggle("Drop set", isOn: true),
                    toggle("Drop set, One extra set at −15%, straight after the last working set.", isOn: true),
                    toggle("Keep the screen awake", isOn: false, .notEnabled),
                    toggle("Keep the screen awake", isOn: true, .notEnabled)
                ]
            ) { LedgerToggleGallery() }
        ]

        nonisolated static let wraps: [TreeCase] = [
            TreeCase("WrapLayout, no child", []) { WrapLayout {} },
            TreeCase(
                "WrapLayout, pill buttons on one row",
                [.button("All", .selected), .button("Chest"), .button("Back")]
            ) { chips(["All", "Chest", "Back"]) },
            TreeCase(
                "WrapLayout, pill buttons over three rows: read in their order, row by row",
                wrapped
            ) { chips(WrapLayoutGallery.muscles + WrapLayoutGallery.equipment.dropFirst()) },
            TreeCase(
                "WrapLayout, three rows at accessibility3",
                at: SnapshotAppearance(.dark, .accessibility3),
                wrapped
            ) { chips(WrapLayoutGallery.muscles + WrapLayoutGallery.equipment.dropFirst()) },
            TreeCase(
                "WrapLayout, right to left: the same order",
                [.button("All", .selected), .button("Chest"), .button("Back")]
            ) { chips(["All", "Chest", "Back"]).environment(\.layoutDirection, .rightToLeft) },
            TreeCase(
                "WrapLayout, a pill longer than the row",
                [.button("Legs", .selected), .button(WrapLayoutGallery.long), .button("Arms")]
            ) { chips(["Legs", WrapLayoutGallery.long, "Arms"]) }
        ]

        /// The thirteen chips of the gallery's second run, the first selected.
        nonisolated static let wrapped: [TreeNode] = [.button("All", .selected)] + [
            "Chest", "Back", "Shoulders", "Legs", "Arms", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight",
            "Kettlebell", "Band"
        ].map { .button($0) }

        /// A field VoiceOver reads as dimmed.
        nonisolated static func dimmed(_ label: String, value: String) -> TreeNode {
            TreeNode(label, value: value, [.adjustable, .notEnabled])
        }

        /// SwiftUI's switch: a button with the switch's own trait, whose value is "1" or "0".
        nonisolated static func toggle(_ label: String, isOn: Bool, _ extra: UIAccessibilityTraits = []) -> TreeNode {
            TreeNode(label, value: isOn ? "1" : "0", switchTraits.union(extra))
        }

        /// What UIKit reports for a SwiftUI switch on iOS 27.0: the button trait and the toggle trait
        /// (`UIAccessibilityTraits.toggleButton`). `LedgerToggleStyleTests` compares the style with a system
        /// switch, so this literal only pins that the two stay what they are.
        nonisolated static let switchTraits: UIAccessibilityTraits = [.button, .toggleButton]

        @MainActor private static func dropSet(_ isOn: Bool) -> some View {
            Toggle(isOn: .constant(isOn)) { Text(verbatim: "Drop set") }.toggleStyle(.ledger)
        }

        @MainActor private static func chips(_ titles: [String]) -> some View {
            WrapLayout {
                ForEach(Array(titles.enumerated()), id: \.offset) { place, title in
                    PillButton(title, style: place == 0 ? .filled : .outline) {}
                }
            }
        }
    }
#endif
