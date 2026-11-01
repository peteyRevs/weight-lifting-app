#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S1, criteria 4 and 8, N4, N5, N7: the intended VoiceOver tree of each state of Settings, pinned exactly
    /// (the stops, their order, labels, values and hints, and which are headings, switches, adjustable and selected),
    /// the 44 pt targets, and what each control sends. Read through UIKit's accessibility tree, as VoiceOver reads it,
    /// from the parts (`SettingsParts`): the screen puts its page in a scroll view, which the hosted reader cannot see
    /// inside (testing-strategy §2.6).
    ///
    /// Each state is read at every text size of `sizes`, which the hosted PR runner cuts to its representatives
    /// (`TestSweep`).
    @Suite("Settings accessibility", .serialized, .tags(.feature))
    struct SettingsAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The tree each state is written to have.
        static func tree(_ preview: SettingsPreview) -> [ViewStop] {
            let model = preview.model()
            let units = model.units
            let rest = model.rest
            let week = model.weekStart
            return [.heading(model.title)]
                + (model.problem.map { [ViewStop.text($0)] } ?? [])
                + [.heading("TRAINING")]
                + units.options.map {
                    ViewStop(kind: .button, label: $0.spokenLabel, hint: units.detail, isSelected: $0.isSelected)
                }
                + [ViewStop(kind: .adjustable, label: rest.title, value: rest.spokenValue, hint: rest.detail)]
                + [ViewStop(kind: .button, label: week.title, value: week.value, hint: week.detail)]
                + model.switches.map { .toggle($0.title, isOn: $0.isOn, hint: $0.detail) }
                + [.heading("DATA"), .text("Apple Health, Not connected"), .button("Diagnostics")]
                + [.text(model.about)]
        }

        @Test(
            "Criteria 4, 8. Every state has exactly its intended VoiceOver tree, at every text size",
            arguments: SettingsPreview.allCases, sizes
        )
        func tree_isExactlyTheTable(_ preview: SettingsPreview, _ size: DynamicTypeSize) {
            let found = SettingsParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("Criterion 2. The rest's shorter step is switched off at 30 s: a swipe down changes nothing")
        func rest_atItsShortest_stepsOnlyUp() {
            var sent: [SettingsAction] = []
            SettingsParts(preview: .saveFailed, send: { sent.append($0) }).withAccessibilityElements { elements in
                let rest = elements.first { $0.accessibilityTraits.contains(.adjustable) }
                rest?.accessibilityDecrement()
                rest?.accessibilityIncrement()
            }
            #expect(sent == [.setDefaultRest(RestDuration(clampingSeconds: 45))])
        }

        @Test(
            "Every button and switch is a target of at least 44 by 44 points",
            arguments: SettingsPreview.allCases,
            sizes
        )
        func targets_areAtLeast44Points(_ preview: SettingsPreview, _ size: DynamicTypeSize) {
            let targets = SettingsParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { [.button, .toggle].contains($0.stop.kind) }
            #expect(targets.count == 7)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }

        @Test("Each control sends the action its model carries: the units, the switches and Diagnostics")
        func controls_sendTheirModelsActions() {
            var sent: [SettingsAction] = []
            let week = SettingsPreview.kilograms.model().weekStart.title
            SettingsParts(preview: .kilograms, send: { sent.append($0) }).withAccessibilityElements { elements in
                // Not the menu, whose activation would present the system's menu.
                for element in elements where element.accessibilityLabel != week {
                    let stop = ViewStop(reading: element)
                    if stop.kind == .button || stop.kind == .toggle {
                        _ = element.accessibilityActivate()
                    }
                }
            }
            #expect(sent == [
                .setUnits(.lb), .setUnits(.kg), .setPlateMath(true), .setAutoRest(false), .setWatchBuzz(true),
                .route(.debugMenu)
            ])
        }
    }
#endif
