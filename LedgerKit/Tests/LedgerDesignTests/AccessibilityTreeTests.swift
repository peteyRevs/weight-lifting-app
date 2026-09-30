#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// One VoiceOver stop, as the table writes it: label, value and traits, and the accessibility
    /// containers between it and the hosting view (their labels, "" for an unlabelled one), all
    /// compared exactly. Every table expects no container: a `.contain` group, labelled or not, is a
    /// structure change (S2-6).
    nonisolated struct TreeNode: Equatable, Sendable, CustomStringConvertible {
        let label: String
        let value: String
        let traits: UInt64
        let containers: [String]

        init(_ label: String, value: String = "", _ traits: UIAccessibilityTraits, containers: [String] = []) {
            self.label = label
            self.value = value
            self.traits = traits.rawValue
            self.containers = containers
        }

        static func button(_ label: String, value: String = "", _ extra: UIAccessibilityTraits = []) -> Self {
            Self(label, value: value, UIAccessibilityTraits.button.union(extra))
        }

        static func text(_ label: String, _ extra: UIAccessibilityTraits = []) -> Self {
            Self(label, UIAccessibilityTraits.staticText.union(extra))
        }

        static func adjustable(_ label: String, value: String) -> Self {
            Self(label, value: value, .adjustable)
        }

        var description: String {
            "\"\(label)\" value \"\(value)\" traits \(traits)" + (containers.isEmpty ? "" : " in \(containers)")
        }
    }

    /// A component in one state, and the tree VoiceOver must find in it.
    nonisolated struct TreeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let appearance: SnapshotAppearance
        let expected: [TreeNode]
        let view: @MainActor @Sendable () -> AnyView

        init(
            _ name: String,
            at appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            _ expected: [TreeNode],
            _ view: @escaping @MainActor @Sendable () -> some View
        ) {
            self.name = name
            self.appearance = appearance
            self.expected = expected
            self.view = { AnyView(view()) }
        }

        var testDescription: String {
            name
        }
    }

    extension RenderingSuites {
        /// Decision of fix round 2 (F06 slice 2): the intended VoiceOver tree of every slice-2
        /// component, in every state it offers, pinned exactly: element count, order, label, value and
        /// traits. The expected trees are literal tables, so any accidental change of structure (an
        /// element added, merged, reordered, relabelled, or a container that carries a label) fails
        /// here. Decorative parts (icons, rules, the ring's arcs, the header's spacer check) appear in
        /// no table because they are no stop. Hit targets and actions are tested beside it.
        @Suite("AccessibilityTree", .tags(.design))
        struct AccessibilityTreeTests {
            @Test(
                "Every slice-2 component in every state has exactly its intended VoiceOver tree",
                arguments: TreeTables.cases
            )
            func component_accessibilityTree_isExactlyTheTable(_ tree: TreeCase) {
                let found = tree.view().withAccessibilityElements(tree.appearance) { elements in
                    elements.map { element in
                        TreeNode(
                            element.accessibilityLabel ?? "",
                            value: element.accessibilityValue ?? "",
                            element.accessibilityTraits,
                            containers: Self.containers(above: element)
                        )
                    }
                }
                #expect(found == tree.expected, "\(tree.name)\n  found:    \(found)\n  expected: \(tree.expected)")
            }

            /// The accessibility containers from `element` up to the hosting view, innermost first.
            /// `accessibilityContainer` is informal on `NSObject` in Swift; SwiftUI's nodes answer it.
            static func containers(above element: NSObject) -> [String] {
                var labels: [String] = []
                var parent = container(of: element)
                while let current = parent, !(current is UIView) {
                    labels.append(current.accessibilityLabel ?? "")
                    parent = container(of: current)
                }
                return labels
            }

            static func container(of object: NSObject) -> NSObject? {
                let selector = NSSelectorFromString("accessibilityContainer")
                guard object.responds(to: selector) else {
                    return nil
                }
                return object.perform(selector)?.takeUnretainedValue() as? NSObject
            }
        }
    }

    /// The tables: every slice-2 component in every state it offers, and its intended tree.
    nonisolated enum TreeTables {
        nonisolated static let cases: [TreeCase] = buttons + labels + lists + sets + rings

        nonisolated static let buttons: [TreeCase] = [
            TreeCase("PrimaryButton with an icon", [.button("Start workout")]) {
                PrimaryButton("Start workout", icon: .arrow) {}
            },
            TreeCase("PrimaryButton, pressed", [.button("Start workout")]) {
                PrimaryButton("Start workout", icon: .arrow) {}.environment(\.ledgerDrawsPressed, true)
            },
            TreeCase("PrimaryButton without an icon", [.button("Resume workout · 12:48")]) {
                PrimaryButton("Resume workout · 12:48") {}
            },
            TreeCase("PrimaryButton, disabled", [.button("Save workout", .notEnabled)]) {
                PrimaryButton("Save workout") {}.disabled(true)
            },
            TreeCase("PillButton, outline", [.button("Finish")]) { PillButton("Finish") {} },
            TreeCase("PillButton, filled (selected)", [.button("Chest", .selected)]) {
                PillButton("Chest", style: .filled) {}
            },
            TreeCase("PillButton, filled and pressed", [.button("Chest", .selected)]) {
                PillButton("Chest", style: .filled) {}.environment(\.ledgerDrawsPressed, true)
            },
            TreeCase("PillButton, ghost", [.button("Skip setup")]) { PillButton("Skip setup", style: .ghost) {} },
            TreeCase("IconPillButton", [.button("Swap exercise")]) {
                IconPillButton("Swap exercise", icon: .swap) {}
            },
            TreeCase("IconPillButton, pressed", [.button("Swap exercise")]) {
                IconPillButton("Swap exercise", icon: .swap) {}.environment(\.ledgerDrawsPressed, true)
            }
        ]

        nonisolated static let labels: [TreeCase] = [
            TreeCase("Eyebrow, accent", [.text("Up next", .header)]) { Eyebrow("Up next", tint: .accent) },
            TreeCase("Eyebrow, muted", [.text("Recent", .header)]) { Eyebrow("Recent") },
            TreeCase("LedgerIconView (decorative)", []) { LedgerIconView(.chevron, sizedAs: .body) },
            TreeCase("HairlineRule (decorative)", []) { HairlineRule() },
            TreeCase("SetRowHeader", [.text("#, lb, reps")]) {
                SetRowHeader(number: "#", weight: "lb", reps: "reps")
            }
        ]

        nonisolated static let lists: [TreeCase] = [
            TreeCase("HairlineRow, title", [.text("Seated Cable Row")]) { HairlineRow("Seated Cable Row") },
            TreeCase("HairlineRow, title and detail", [.text("Lower A, Mon · 58 min")]) {
                HairlineRow("Lower A", detail: "Mon · 58 min")
            },
            TreeCase("HairlineRow, text accessory", [.text("Barbell Bench Press, 5 × 5 @ 185")]) {
                HairlineRow("Barbell Bench Press") { Text(verbatim: "5 × 5 @ 185") }
            },
            TreeCase("HairlineRow, button accessory (one stop)", [.button("Dumbbell Bench Press, Use")]) {
                HairlineRow("Dumbbell Bench Press") { PillButton("Use", style: .ghost) {} }
            },
            TreeCase("HairlineRow, action and chevron", [.button("Lower A, Mon · 58 min")]) {
                HairlineRow("Lower A", detail: "Mon · 58 min") {} accessory: {
                    LedgerIconView(.chevron, sizedAs: .body)
                }
            },
            TreeCase("HairlineRow, action, pressed", [.button("Seated Cable Row")]) {
                HairlineRow("Seated Cable Row", action: {}).environment(\.ledgerDrawsPressed, true)
            },
            TreeCase("HairlineList of two rows", [.text("Barbell Bench Press"), .text("Seated Cable Row")]) {
                HairlineList {
                    HairlineRow("Barbell Bench Press")
                    HairlineRow("Seated Cable Row")
                }
            }
        ]

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
            TreeCase(
                "SetRow, done, named by the feature",
                [
                    .button("Set 2, 185 pounds, 5 reps", value: "Done"),
                    .button("Undo set 2", value: "Done", .selected)
                ]
            ) { row(.done, check: "Undo set 2").accessibilityLabel("Set 2, 185 pounds, 5 reps") },
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

        nonisolated static let rings: [TreeCase] = [
            TreeCase("RestRing, full", [.text("2:30", .updatesFrequently)]) { RestRing(progress: 1, label: "2:30")
            },
            TreeCase("RestRing, half", [.text("1:15", .updatesFrequently)]) {
                RestRing(progress: 0.5, label: "1:15")
            },
            TreeCase("RestRing, empty", [.text("0:00", .updatesFrequently)]) { RestRing(progress: 0, label: "0:00")
            },
            TreeCase(
                "RestRing, named by the feature",
                [.text("Rest, 1 minute 15 seconds left", .updatesFrequently)]
            ) {
                RestRing(progress: 0.5, label: "1:15").accessibilityLabel("Rest, 1 minute 15 seconds left")
            }
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
