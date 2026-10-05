#if os(iOS)
    @testable import FeatureOnboarding
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// One VoiceOver stop, as the tables write it: label, value and traits, compared exactly.
    nonisolated struct Stop: Equatable, Sendable, CustomStringConvertible {
        let label: String
        let value: String
        let traits: UInt64

        init(_ label: String, value: String = "", _ traits: UIAccessibilityTraits) {
            self.label = label
            self.value = value
            self.traits = traits.rawValue
        }

        /// A button; `extra` adds `.selected` or `.notEnabled`.
        static func button(_ label: String, _ extra: UIAccessibilityTraits = []) -> Stop {
            Stop(label, UIAccessibilityTraits.button.union(extra))
        }

        static func text(_ label: String) -> Stop {
            Stop(label, .staticText)
        }

        /// The screen's title: a heading.
        static func heading(_ label: String) -> Stop {
            Stop(label, [.header, .staticText])
        }

        /// The three bars: one element, a label and no value.
        static func progress(_ label: String) -> Stop {
            Stop(label, [])
        }

        var description: String {
            "\"\(label)\" value \"\(value)\" traits \(traits)"
        }
    }

    /// The screen in one state, and the tree VoiceOver must find in it.
    nonisolated struct OnboardingTree: Sendable, CustomTestStringConvertible {
        let name: String
        let state: OnboardingState
        let expected: [Stop]

        var testDescription: String {
            name
        }
    }

    /// F08 S2, criterion 8: the intended VoiceOver tree of each step and of the failure state, as the
    /// implementation notes write them, pinned exactly: the stops, their order, labels, values and traits. Read
    /// through UIKit's accessibility tree, as VoiceOver reads it, at the default text size and at the largest of
    /// the snapshot matrix.
    ///
    /// The trees are read from the page followed by the pinned part (`OnboardingParts`), not from the screen:
    /// the screen puts the page in a scroll view, which the hosted reader cannot see inside (testing-strategy
    /// §2.6). The same stops in the same order inside the real scroll view are S3's nightly UI test.
    @Suite("Onboarding accessibility", .serialized, .tags(.feature))
    struct OnboardingAccessibilityTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility3)
        ]

        @Test(
            "Every state has exactly its intended VoiceOver tree, at the default and the largest text size",
            arguments: OnboardingTrees.all
        )
        func tree_isExactlyTheTable(_ tree: OnboardingTree) {
            for appearance in Self.appearances {
                let found = OnboardingParts(tree.state).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                #expect(
                    found == tree.expected,
                    "\(tree.name) at \(appearance)\n  found:    \(found)\n  expected: \(tree.expected)"
                )
            }
        }

        @Test(
            "Every button's target is at least 44 by 44 points, at the default and the largest text size",
            arguments: OnboardingTrees.all
        )
        func buttons_haveA44PointTarget(_ tree: OnboardingTree) {
            for appearance in Self.appearances {
                let buttons = OnboardingParts(tree.state).accessibilityElements(appearance)
                    .filter { $0.traits.contains(.button) }
                #expect(buttons.count >= 2)
                for button in buttons {
                    // UIKit's conversion to window coordinates can report 44 pt as 43.999999999999886.
                    #expect(
                        button.frame.width >= 44 - 0.001 && button.frame.height >= 44 - 0.001,
                        "\(button.label) at \(appearance): \(button.frame.size)"
                    )
                }
            }
        }

        @Test("A tap on an option sends its pick, and each button sends its model's action")
        func activating_sendsTheModelsAction() {
            var sent: [OnboardingAction] = []
            OnboardingParts(OnboardingState(step: .days)) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    #expect(element.accessibilityActivate(), "\(element.accessibilityLabel ?? "")")
                }
            }
            #expect(sent == [
                .back, .pickDays(.three), .pickDays(.four), .pickDays(.five), .pickDays(.six), .advance, .skipSetup
            ])
        }

        @Test("Step 3's days are not buttons: activating one sends nothing")
        func days_areNotTappable() {
            var sent: [OnboardingAction] = []
            OnboardingParts(OnboardingState(step: .program)) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where !element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.isEmpty)
        }

        @Test("A locked control sends nothing", arguments: [OnboardingState.Phase.saving, .retrying, .saved])
        func lockedControls_sendNothing(_ phase: OnboardingState.Phase) {
            var sent: [OnboardingAction] = []
            let state = OnboardingState(step: .days, phase: phase)
            OnboardingParts(state) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.isEmpty)
        }
    }
#endif
