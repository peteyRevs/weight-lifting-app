#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S2, criterion 3 and N12, hosted: the plates sheet's VoiceOver tree, pinned exactly (the bar one adjustable
    /// element, each plate a switch named by its spoken weight, on or off as its value, the line when none is, "Reset
    /// to standard" and "Done"), what each control sends, and its layout at every text size, read from its parts
    /// (`PlatesParts`). Each state is read at the sizes `TestSweep` keeps on the hosted PR runner.
    @Suite("Plates sheet", .serialized, .tags(.feature))
    struct PlateInventorySheetTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .accessibility3, .accessibility5])

        static func tree(_ preview: PlatesPreview) -> [ViewStop] {
            let model = preview.model()
            let bar = model.bar
            return [ViewStop.adjustable(bar.title, value: bar.spokenValue), .heading(model.platesTitle)]
                + model.plates.map { plate in
                    ViewStop(
                        kind: .toggle,
                        label: plate.spokenLabel,
                        value: plate.isOn ? "1" : "0",
                        isSelected: false
                    )
                }
                + (model.empty.map { [ViewStop.text($0)] } ?? [])
                + [.button(model.reset.title), .button(model.done.title)]
        }

        @Test(
            "Criterion 3, N12. Every state has exactly its intended VoiceOver tree",
            arguments: PlatesPreview.allCases,
            sizes
        )
        func tree_isExactlyTheTable(_ preview: PlatesPreview, _ size: DynamicTypeSize) {
            let found = PlatesParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("Each control sends its model's action: the bar's steps, each plate, Reset and Done")
        func controls_sendTheirActions() {
            var sent: [SettingsAction] = []
            PlatesParts(preview: .pounds, send: { sent.append($0) }).withAccessibilityElements { elements in
                for element in elements {
                    if element.accessibilityTraits.contains(.adjustable) {
                        element.accessibilityIncrement()
                        element.accessibilityDecrement()
                    } else if element.accessibilityTraits.contains(.button) {
                        _ = element.accessibilityActivate()
                    }
                }
            }
            let model = PlatesPreview.pounds.model()
            let expected = [model.bar.increment, model.bar.decrement].compactMap(\.self) + model.plates.map(\.action)
                + [.resetPlates, .savePlates]
            let sentEach = sent == expected
            #expect(sentEach, "\(sent.count) sent")
        }

        @Test(
            "In every state and size no stop is empty, outside the sheet, under 44 points or over another",
            arguments: PlatesPreview.allCases,
            sizes
        )
        func parts_layOutSanely(_ preview: PlatesPreview, _ size: DynamicTypeSize) {
            let stops = PlatesParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
            #expect(stops.count >= 10, "the parts were not read")
            let faults = SettingsLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }
    }

    /// F14 S2: the plates sheet against its references, at the iPhone 17 width and its own height. Pounds and
    /// kilograms in light and dark at the default size, and pounds at an accessibility size: six references.
    @Suite("Plates sheet snapshots", .serialized, .tags(.feature, .snapshot))
    struct PlateInventorySheetSnapshotTests {
        private func parts(_ preview: PlatesPreview) -> some View {
            PlatesParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The sheet in pounds matches its references, at the default and an accessibility size")
        func pounds_matchesReferences() {
            assertLedgerSnapshot(of: parts(.pounds), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("The sheet in kilograms, with a size off the list, matches its references")
        func kilograms_matchesReferences() {
            assertLedgerSnapshot(of: parts(.kilograms), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
