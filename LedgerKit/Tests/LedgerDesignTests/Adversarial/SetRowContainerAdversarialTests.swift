#if os(iOS)
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F06 slice 2, adversarial round 2 (close-out): what fix round 1's `.contain` on the set row's
        /// check does to a label set from outside. `accessibilityElements` returns VoiceOver's stops;
        /// these tests also read the containers above them, whose labels VoiceOver can speak when it
        /// moves into them (UIKit's `semanticGroup`; SwiftUI's own `.contain` example labels its
        /// containers for that purpose).
        @Suite("SetRow containers (adversarial, slice 2 round 2)", .tags(.design))
        struct SetRowContainerAdversarialTests {
            /// The non-empty labels on the containers between an element and the hosting view.
            static func containerLabels(above element: NSObject) -> [String] {
                var labels: [String] = []
                var node = container(of: element)
                while let current = node, !(current is UIView) {
                    if let label = current.accessibilityLabel, !label.isEmpty {
                        labels.append(label)
                    }
                    node = container(of: current)
                }
                return labels
            }

            /// `accessibilityContainer` is informal on `NSObject` in Swift; SwiftUI's nodes answer it.
            static func container(of object: NSObject) -> NSObject? {
                let selector = NSSelectorFromString("accessibilityContainer")
                guard object.responds(to: selector) else {
                    return nil
                }
                return object.perform(selector)?.takeUnretainedValue() as? NSObject
            }

            /// Positive control: with no label from outside, the check's container is unlabelled, so
            /// VoiceOver has nothing to say on the way in.
            @Test("Without a label from outside, no container in a SetRow is labelled")
            func setRow_noOuterLabel_containersAreUnlabelled() {
                let labels = AccessibilityCases.setRow(.done).withAccessibilityElements { elements in
                    elements.flatMap(Self.containerLabels(above:))
                }
                #expect(labels.isEmpty, "\(labels)")
            }

            /// The row reads "Set 2, 185 pounds, 5 reps, Done". The same words should not come again
            /// when VoiceOver moves on to the check: its container must not carry the row's label.
            @Test(
                "A label set on a SetRow from outside does not also label the container around its check",
                arguments: [SetRowState.pending, .active, .done]
            )
            func setRow_outerLabel_doesNotLabelTheCheckContainer(_ state: SetRowState) throws {
                let spoken = "Set 2, 185 pounds, 5 reps"
                // Fix round 3 (S2-8): the spoken label is `accessibilitySummary`; assertions unchanged.
                let found = AccessibilityCases.setRow(state, summary: spoken)
                    .withAccessibilityElements { elements in
                        elements.map { ($0.accessibilityLabel ?? "", Self.containerLabels(above: $0)) }
                    }
                try #require(found.count == 2, "\(found)")
                #expect(found[0].0 == spoken)
                #expect(found[1].0 == "Log set 2")
                for (label, containers) in found {
                    #expect(containers.isEmpty, "\(state): \"\(label)\" sits in a container labelled \(containers)")
                }
            }
        }
    }
#endif
