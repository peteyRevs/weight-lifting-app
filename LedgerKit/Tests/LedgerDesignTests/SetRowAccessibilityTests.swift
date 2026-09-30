#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F06 criterion 6 for the set row and its steppers, and slice 2 fix round 1 (S2-1 to S2-3):
        /// what VoiceOver reads for each state, a spoken label a feature sets from outside, and the
        /// steppers' values.
        @Suite("SetRowAccessibility", .tags(.design))
        struct SetRowAccessibilityTests {
            nonisolated static let sizes = ComponentAccessibilityTests.sizes

            static func row(_ state: SetRowState) -> SetRow {
                SetRow(number: "2", weight: "185", reps: "5", state: state, checkLabel: "Log set 2") {} onCheck: {}
            }

            @Test(
                "SetRow: the row and its check are labelled buttons with 44 pt targets",
                arguments: [SetRowState.pending, .active, .done]
            )
            func setRow_accessibility_rowAndCheckAreButtons(_ state: SetRowState) throws {
                for appearance in Self.sizes {
                    let elements = Self.row(state).accessibilityElements(appearance)
                    try #require(elements.count == 2, "\(elements)")
                    let (select, check) = (elements[0], elements[1])
                    #expect(select.label == "2, 185, 5") // exact: "185" contains "5" (review R2-N8)
                    expectButton(select)
                    #expect(check.label == "Log set 2")
                    expectButton(check)
                }
            }

            /// S2-1: each state says what it is in words, and "selected" means one thing: logged.
            @Test(
                "SetRow: the row says its state in words; only a logged check is selected, and it says 'Done'",
                arguments: [
                    (SetRowState.pending, "Pending", ""),
                    (SetRowState.active, "Current set", ""),
                    (SetRowState.done, "Done", "Done")
                ]
            )
            func setRow_state_isSpokenInWords(_ state: SetRowState, rowValue: String, checkValue: String) throws {
                let elements = Self.row(state).accessibilityElements()
                try #require(elements.count == 2, "\(elements)")
                let (select, check) = (elements[0], elements[1])
                #expect(select.value == rowValue, "\(select)")
                #expect(!select.traits.contains(.selected), "\(select)")
                #expect(check.value == checkValue, "\(check)")
                #expect(check.traits.contains(.selected) == (state == .done), "\(check)")
            }

            /// S2-3: a feature's spoken label reaches the row, and the check keeps its own.
            @Test("SetRow: a spoken label from outside names the row, keeps the state and leaves the check alone")
            func setRow_outerLabel_namesTheRowOnly() throws {
                let spoken = "Set 2, 185 pounds, 5 reps"
                let elements = Self.row(.done).accessibilityLabel(spoken).accessibilityElements()
                try #require(elements.count == 2, "\(elements)")
                #expect(elements[0].label == spoken)
                #expect(elements[0].value == "Done")
                #expect(elements[1].label == "Log set 2")
                #expect(elements[1].value == "Done")
            }

            @Test("SetRow: activating the row selects it; activating the check logs it")
            func setRow_activation_callsTheMatchingAction() {
                var calls: [String] = []
                let row = SetRow(number: "2", weight: "185", reps: "5", state: .pending, checkLabel: "Log set 2") {
                    calls.append("select")
                } onCheck: {
                    calls.append("check")
                }
                row.withAccessibilityElements { elements in
                    _ = elements.first?.accessibilityActivate()
                    _ = elements.last?.accessibilityActivate()
                }
                #expect(calls == ["select", "check"])
            }

            @Test(
                "SetRowSteppers: each stepper is one adjustable element named by its step, 44 pt tall",
                arguments: sizes
            )
            func setRowSteppers_accessibility_twoAdjustableSteppers(_ appearance: SnapshotAppearance) throws {
                let elements = SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { _ in },
                    onReps: { _ in }
                )
                .accessibilityElements(appearance)
                try #require(elements.count == 2, "\(elements)")
                #expect(elements.map(\.label) == ["5 lb", "1 rep"])
                for stepper in elements {
                    #expect(stepper.traits.contains(.adjustable))
                    expectTarget(stepper)
                }
            }

            /// S2-2, S2-7: the value is the current weight and reps, in the caller's words and units. The
            /// values are required, so there is no fallback to test (fix round 2 removed the half that
            /// pinned the step as a value, which the tester rejected).
            @Test("SetRowSteppers: each stepper's value is the current weight or reps")
            func setRowSteppers_value_isTheCurrentQuantity() {
                let given = SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { _ in },
                    onReps: { _ in }
                )
                #expect(given.accessibilityElements().map(\.value) == ["185 pounds", "5 reps"])
            }

            /// S2-2: swipe up, and the value VoiceOver announces next is the new weight.
            @Test("SetRowSteppers: VoiceOver's increment and decrement change the value it announces")
            func setRowSteppers_adjust_changesTheAnnouncedValue() {
                SteppersHarness().withLiveAccessibilityElements { read in
                    #expect(read().map { $0.accessibilityValue ?? "" } == ["185 pounds", "5 reps"])
                    read().first?.accessibilityIncrement()
                    #expect(read().first?.accessibilityValue == "190 pounds")
                    read().last?.accessibilityDecrement()
                    read().last?.accessibilityDecrement()
                    #expect(read().last?.accessibilityValue == "3 reps")
                }
            }

            @Test("SetRowSteppers: VoiceOver's swipe up and down step the right value the right way")
            func setRowSteppers_adjust_stepsTheMatchingValue() {
                var steps: [String] = []
                let steppers = SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { steps.append("weight \($0)") },
                    onReps: { steps.append("reps \($0)") }
                )
                steppers.withAccessibilityElements { elements in
                    elements.first?.accessibilityIncrement()
                    elements.first?.accessibilityDecrement()
                    elements.last?.accessibilityIncrement()
                }
                #expect(steps == ["weight increment", "weight decrement", "reps increment"])
            }
        }
    }

    /// Steppers wired to state, as a feature's store would wire them.
    private struct SteppersHarness: View {
        @State private var weight = 185
        @State private var reps = 5

        var body: some View {
            SetRowSteppers(
                weightStep: "5 lb",
                repStep: "1 rep",
                weight: "\(weight) pounds",
                reps: "\(reps) reps",
                onWeight: { weight += $0 == .increment ? 5 : -5 },
                onReps: { reps += $0 == .increment ? 1 : -1 }
            )
        }
    }
#endif
