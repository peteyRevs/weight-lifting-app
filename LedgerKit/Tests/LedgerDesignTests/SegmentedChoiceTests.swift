#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// An option of the choice under test: a title drawn, and a name spoken.
    private struct Option: Identifiable, Equatable {
        let id: Int
        let title: String
        let spoken: String
    }

    extension RenderingSuites {
        /// F14 S1, N5 and N10 (A5): each option of `SegmentedChoice` is a button read by its spoken name, the chosen
        /// one selected; every option is a 44 pt target; the options keep one row and one line at every text size;
        /// and a tap hands the caller the option it chose. The group around them, named by the label, is not in the
        /// hosted reader's flat list of stops (it walks into containers); VoiceOver's reading of it is the DoD's check
        /// on the simulator.
        @Suite("SegmentedChoice", .tags(.design))
        struct SegmentedChoiceTests {
            private static let units = [
                Option(id: 0, title: "LB", spoken: "pounds"), Option(id: 1, title: "KG", spoken: "kilograms")
            ]

            private static func choice(chosen: Int, onSelect: @escaping (Option) -> Void = { _ in }) -> some View {
                SegmentedChoice(
                    "Units",
                    options: units,
                    title: \.title,
                    spokenLabel: \.spoken,
                    isSelected: { $0.id == chosen },
                    onSelect: onSelect
                )
            }

            @Test("Each option is a button read by its spoken name, the chosen one selected", arguments: [0, 1])
            func options_readTheirNames_andTheChosenIsSelected(_ chosen: Int) {
                let elements = Self.choice(chosen: chosen).accessibilityElements()
                #expect(elements.map(\.label) == ["pounds", "kilograms"])
                #expect(elements.map { $0.traits.contains(.button) } == [true, true])
                #expect(elements.map { $0.traits.contains(.selected) } == [chosen == 0, chosen == 1])
            }

            @Test(
                "Every option is a 44 pt target, and the two keep one row at every text size",
                arguments: [DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5]
            )
            func options_areTargets_onOneRow(_ size: DynamicTypeSize) throws {
                let elements = Self.choice(chosen: 1).accessibilityElements(SnapshotAppearance(.light, size))
                try #require(elements.count == 2)
                for element in elements {
                    expectTarget(element)
                }
                let (first, second) = (elements[0].frame, elements[1].frame)
                #expect(second.minX >= first.maxX - 0.5, "the options stand side by side: \(first) \(second)")
                #expect(abs(first.height - second.height) < 0.5 && abs(first.minY - second.minY) < 0.5)
                let line = try #require(Text(verbatim: "KG").ledgerFont(.caption).accessibilityElements(
                    SnapshotAppearance(.light, size)
                ).first).frame.height
                let oneLine = max(44, line + 2 * LedgerSpacing.s)
                #expect(first.height <= oneLine + 0.5, "a title wrapped at \(size): \(first.height) for \(oneLine)")
            }

            @Test("Activating an option hands the caller that option")
            func activating_handsTheChosenOption() {
                var chosen: [Option] = []
                Self.choice(chosen: 0) { chosen.append($0) }.withAccessibilityElements { elements in
                    for element in elements.reversed() {
                        _ = element.accessibilityActivate()
                    }
                }
                #expect(chosen == Self.units.reversed())
            }
        }
    }
#endif
