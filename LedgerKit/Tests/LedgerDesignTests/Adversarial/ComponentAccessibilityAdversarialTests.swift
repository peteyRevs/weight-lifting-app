#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// A tappable component and the number of buttons VoiceOver should find in it.
    struct TappableCase {
        let name: String
        let view: AnyView
        let buttons: Int

        init(_ name: String, _ view: some View, buttons: Int = 1) {
            self.name = name
            self.view = AnyView(view)
            self.buttons = buttons
        }
    }

    /// The components the accessibility suite reads.
    enum AccessibilityCases {
        /// Every tappable slice-2 component, with the number of buttons VoiceOver should find in it.
        static func tappables() -> [TappableCase] {
            [
                TappableCase("PrimaryButton with icon", PrimaryButton("Start workout", icon: .arrow) {}),
                TappableCase("PrimaryButton", PrimaryButton("Resume workout · 12:48") {}),
                TappableCase("PillButton outline", PillButton("Finish") {}),
                TappableCase("PillButton filled", PillButton("Chest", style: .filled) {}),
                TappableCase("PillButton ghost, short", PillButton("Skip", style: .ghost) {}),
                TappableCase("IconPillButton", IconPillButton("Swap exercise", icon: .swap) {}),
                TappableCase("HairlineRow with action, no detail", HairlineRow("Seated Cable Row", action: {})),
                TappableCase(
                    "HairlineRow with action and chevron",
                    HairlineRow("Lower A", detail: "Mon · 58 min", action: {}, accessory: {
                        LedgerIconView(.chevron, sizedAs: .body)
                    })
                ),
                TappableCase("SetRow pending", setRow(.pending), buttons: 2),
                TappableCase("SetRow active", setRow(.active), buttons: 2),
                TappableCase("SetRow done", setRow(.done), buttons: 2),
                TappableCase("SetRow drop set", setRow(.pending, number: "D"), buttons: 2)
            ]
        }

        /// `summary` added in F06 slice 2 fix round 3 (S2-8, Pete's re-plan): the row's spoken name is
        /// an initializer parameter now, not a label applied from outside.
        static func setRow(_ state: SetRowState, number: String = "2", summary: String? = nil) -> SetRow {
            SetRow(
                number: number,
                weight: "185",
                reps: "5",
                state: state,
                checkLabel: "Log set \(number)",
                accessibilitySummary: summary
            ) {} onCheck: {}
        }
    }

    extension RenderingSuites {
        /// F06 slice 2, adversarial round 1: the slice-2 components through UIKit's accessibility tree,
        /// as VoiceOver reads them, beyond `ComponentAccessibilityTests`' two text sizes: the smallest,
        /// the largest non-accessibility and the largest accessibility size; what a done set, a
        /// stepper and a decorative part say; and what a feature can change from outside.
        @Suite("Component accessibility (adversarial, slice 2 round 1)", .tags(.design))
        struct ComponentAccessibilityAdversarialTests {
            nonisolated static let extremes = [
                SnapshotAppearance(.light, .xSmall),
                SnapshotAppearance(.dark, .xxxLarge),
                SnapshotAppearance(.dark, .accessibility5)
            ]

            static func isTarget(_ element: AccessibilityElementSnapshot) -> Bool {
                element.frame.width >= 44 - 0.001 && element.frame.height >= 44 - 0.001
            }

            @Test(
                "Every tappable component is a labelled button with a 44 pt target at xSmall, xxxLarge and AX5",
                arguments: extremes
            )
            func tappables_atExtremeTextSizes_areLabelledButtonsWithTargets(_ appearance: SnapshotAppearance) {
                for tappable in AccessibilityCases.tappables() {
                    let name = tappable.name
                    let elements = tappable.view.accessibilityElements(appearance)
                    let buttons = elements.filter { $0.traits.contains(.button) }
                    #expect(buttons.count == tappable.buttons, "\(name) \(appearance): \(elements)")
                    for button in buttons {
                        #expect(!button.label.isEmpty, "\(name) \(appearance): unlabelled \(button)")
                        #expect(Self.isTarget(button), "\(name) \(appearance): \(button.frame.size) is under 44 × 44")
                    }
                }
            }

            @Test("Each stepper is adjustable with a 44 pt target at xSmall, xxxLarge and AX5", arguments: extremes)
            func steppers_atExtremeTextSizes_areAdjustableTargets(_ appearance: SnapshotAppearance) throws {
                let elements = SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { _ in },
                    onReps: { _ in }
                )
                .accessibilityElements(appearance)
                try #require(elements.count == 2, "\(appearance): \(elements)")
                for stepper in elements {
                    #expect(stepper.traits.contains(.adjustable), "\(appearance): \(stepper)")
                    #expect(Self.isTarget(stepper), "\(appearance): \(stepper)")
                }
            }

            /// Sighted users see a done set by its muted numbers and filled disc. VoiceOver's row element
            /// (the one that selects the set) should say so too. (Since S2-1 the row is never selected; its
            /// value names the state. Comment updated in F06 slice 2 fix round 2, R2-N11.)
            @Test("A done set's row element reads differently from a pending set's")
            func setRow_doneRow_isDistinguishableFromPending() throws {
                let done = AccessibilityCases.setRow(.done).accessibilityElements()
                let pending = AccessibilityCases.setRow(.pending).accessibilityElements()
                let doneRow = try #require(done.first)
                let pendingRow = try #require(pending.first)
                #expect(
                    doneRow.label != pendingRow.label || doneRow.value != pendingRow.value
                        || doneRow.traits != pendingRow.traits,
                    "done \(doneRow) and pending \(pendingRow) read the same"
                )
            }

            /// The check's done state is the `selected` trait, the same word the row uses for "active".
            @Test("A done set's check says 'done' in words, not only with the 'selected' trait")
            func setRow_doneCheck_saysDoneInWords() throws {
                let check = try #require(AccessibilityCases.setRow(.done).accessibilityElements().last)
                let pendingCheck = try #require(AccessibilityCases.setRow(.pending).accessibilityElements().last)
                #expect(check.traits.contains(.selected))
                #expect(
                    check.value != pendingCheck.value || check.label != pendingCheck.label,
                    "done check \(check), pending check \(pendingCheck): only the trait differs"
                )
            }

            /// VoiceOver announces an adjustable element's value after each swipe. Without one, a swipe
            /// up on "5 lb" says nothing about the weight it changed.
            @Test("Each stepper has a value for VoiceOver to announce after a swipe")
            func steppers_adjustable_haveAValue() throws {
                let elements = SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { _ in },
                    onReps: { _ in }
                )
                .accessibilityElements()
                try #require(elements.count == 2)
                for stepper in elements {
                    #expect(!stepper.value.isEmpty, "\(stepper)")
                }
            }

            /// VoiceOver reads the row as its three strings: "2, 185, 5". A feature that wants
            /// "Set 2, 185 pounds, 5 reps" can only wrap the component from outside.
            @Test("A feature can relabel a set row for VoiceOver without renaming its check")
            func setRow_outerLabel_relabelsTheRowOnly() throws {
                let spoken = "Set 2, 185 pounds, 5 reps"
                // Fix round 3 (S2-8): the spoken label is `accessibilitySummary`; assertions unchanged.
                let elements = AccessibilityCases.setRow(.pending, summary: spoken).accessibilityElements()
                try #require(elements.count == 2, "\(elements)")
                #expect(elements[0].label == spoken, "row: \(elements[0])")
                #expect(elements[1].label == "Log set 2", "check: \(elements[1])")
            }

            /// VoiceOver reads a bare "2:30" like a time of day. The ring is one element, so a feature can
            /// say "Rest, 2 minutes 30 seconds left" from outside.
            @Test("A feature can give the ring a spoken countdown in place of its clock-style label")
            func restRing_outerLabel_replacesTheClockLabel() throws {
                let spoken = "Rest, 2 minutes 30 seconds left"
                let elements = RestRing(progress: 1, label: "2:30").accessibilityLabel(spoken).accessibilityElements()
                try #require(elements.count == 1, "\(elements)")
                #expect(elements[0].label == spoken)
            }

            @Test("Decorative parts are hidden: icons, rules, the header's spacer check, the ring's arcs")
            func decorativeParts_areHidden() {
                let iconAndText = VStack {
                    LedgerIconView(.check, sizedAs: .body)
                    Text(verbatim: "Done")
                }.accessibilityElements()
                #expect(iconAndText.map(\.label) == ["Done"], "\(iconAndText)")

                let header = SetRowHeader(number: "#", weight: "lb", reps: "reps").accessibilityElements()
                #expect(!header.contains { $0.traits.contains(.button) }, "the hidden check is read: \(header)")

                let list = HairlineList {
                    HairlineRow("Barbell Bench Press")
                    HairlineRow("Seated Cable Row")
                }.accessibilityElements()
                #expect(list.map(\.label) == ["Barbell Bench Press", "Seated Cable Row"], "\(list)")

                let ring = RestRing(progress: 0.5, label: "1:15").accessibilityElements()
                #expect(ring.count == 1, "\(ring)")

                let icon = IconPillButton("Swap exercise", icon: .swap) {}.accessibilityElements()
                #expect(icon.count == 1 && icon.first?.label == "Swap exercise", "\(icon)")
            }

            /// v2's swap sheet has a "Use" at the end of a row. A row without its own action keeps its
            /// children as one element; a button inside must still be reachable and work.
            @Test("A HairlineRow without an action keeps a button accessory reachable and working")
            func hairlineRow_buttonAccessory_isReachable() {
                var used = 0
                let row = HairlineRow("Dumbbell Bench Press", detail: "Similar pattern · 2 × 70 lb") {
                    PillButton("Use", style: .ghost) { used += 1 }
                }
                row.withAccessibilityElements { elements in
                    let buttons = elements.filter { $0.accessibilityTraits.contains(.button) }
                    #expect(!buttons.isEmpty, "no button among \(elements.map { $0.accessibilityLabel ?? "" })")
                    _ = buttons.first?.accessibilityActivate()
                }
                #expect(used == 1)
            }

            @Test("Disabled pills and round buttons tell VoiceOver they are dimmed")
            func disabledSecondaryButtons_areNotEnabled() throws {
                for view in [
                    AnyView(PillButton("Finish") {}.disabled(true)),
                    AnyView(PillButton("Chest", style: .filled) {}.disabled(true)),
                    AnyView(IconPillButton("Swap exercise", icon: .swap) {}.disabled(true))
                ] {
                    let button = try #require(view.accessibilityElements().first)
                    #expect(button.traits.contains(.notEnabled), "\(button)")
                }
            }
        }
    }
#endif
