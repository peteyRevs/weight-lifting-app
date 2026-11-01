#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// An option of the choice under attack.
    private struct AttackOption: Identifiable {
        let id: Int
        let title: String
    }

    extension RenderingSuites {
        /// F14 S1b, G2: `SegmentedChoice` pushed past Settings' "LB" and "KG": the gallery's own three options at
        /// the largest sizes, right to left, disabled, and a tap on the chosen option.
        @Suite("SegmentedChoice, adversarial", .tags(.design))
        struct SegmentedChoiceAdversarialTests {
            private static func choice(
                _ titles: [String],
                chosen: Int,
                onSelect: @escaping (AttackOption) -> Void = { _ in }
            ) -> some View {
                SegmentedChoice(
                    "Side",
                    hint: "Which side",
                    options: titles.enumerated().map { AttackOption(id: $0.offset, title: $0.element) },
                    title: \.title,
                    spokenLabel: \.title,
                    isSelected: { $0.id == chosen },
                    onSelect: onSelect
                )
            }

            /// The choice on a page: the screen's margins either side, as a row of Settings would place it under
            /// its label at an accessibility size.
            private static func onAPage(_ view: some View) -> some View {
                view.padding(.horizontal, LedgerSpacing.screen).frame(maxWidth: .infinity, alignment: .leading)
            }

            @Test(
                "The gallery's three options keep inside a phone's page at every size",
                arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5]
            )
            func threeOptions_fitThePage(_ size: DynamicTypeSize) throws {
                let elements = Self.onAPage(Self.choice(["Left", "Both", "Right"], chosen: 1))
                    .accessibilityElements(SnapshotAppearance(.light, size))
                try #require(elements.count == 3)
                let right = SnapshotConfig.phoneWidth - LedgerSpacing.screen
                let overflow = (elements.map(\.frame.maxX).max() ?? 0) - right
                #expect(overflow <= 0.5, "at \(size) the last option ends \(overflow) pt past the page's margin")
            }

            @Test("Right to left the first option stands on the right, each still a 44 pt target, the hint on each")
            func rightToLeft_mirrors() throws {
                let elements = Self.choice(["LB", "KG"], chosen: 0)
                    .environment(\.layoutDirection, .rightToLeft)
                    .withAccessibilityElements { elements in
                        elements
                            .map { ($0.accessibilityLabel ?? "", $0.accessibilityHint ?? "", $0.accessibilityFrame) }
                    }
                try #require(elements.count == 2)
                #expect(elements.map(\.0) == ["LB", "KG"], "VoiceOver reads them in the reading order")
                #expect(elements[0].2.minX > elements[1].2.minX)
                #expect(elements.allSatisfy { $0.1 == "Which side" })
                #expect(elements.allSatisfy { $0.2.width >= 43.5 && $0.2.height >= 43.5 })
            }

            @Test("Disabled, every option is dimmed to VoiceOver, and an activation chooses nothing")
            func disabled_choosesNothing() {
                var chosen: [Int] = []
                let traits = Self.choice(["LB", "KG"], chosen: 0) { chosen.append($0.id) }
                    .disabled(true)
                    .withAccessibilityElements { elements in
                        for element in elements {
                            _ = element.accessibilityActivate()
                        }
                        return elements.map(\.accessibilityTraits)
                    }
                #expect(traits.count == 2)
                #expect(traits.allSatisfy { $0.contains(.notEnabled) })
                #expect(chosen.isEmpty)
            }
        }
    }
#endif
