#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S8b criteria 13, 32 and 33: the swap sheet and the card's title row as VoiceOver meets them,
    /// from `.large` to `.accessibility5`, with a name long enough to wrap. The tree below was written from
    /// the contract before the views were read:
    ///
    /// | # | Label | Value | Kind |
    /// |---|---|---|---|
    /// | 1 | Swap exercise | | heading |
    /// | 2 | Cancel | | button |
    /// | 3 | Same movement pattern. | | text |
    /// | 4 | Also update program | on/off | switch |
    /// | 5… | "Dumbbell Bench Press, Dumbbell · 15 lb, Use" | | button |
    @MainActor
    @Suite("Swap sheet's VoiceOver tree (adversarial)", .serialized, .tags(.feature))
    struct WorkoutSwapTreeAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]
        static let longName = "Single-Arm Half-Kneeling Landmine Press With A Two-Second Pause"

        /// The sheet for the seed workout's bench press, its rows as the store would hold them.
        static func sheet(isOn: Bool = false, longRow: Bool = false) throws -> SwapSheetModel {
            let workout = try SwapG2Catalog.workout()
            var picked = try ["Dumbbell Bench Press", "Weighted Dip", "Decline Push-Up"].map(SwapG2Catalog.named)
            if longRow {
                // Another catalog exercise under a long name, so the row has an id of its own.
                var long = try SwapG2Catalog.named("Machine Chest Press")
                long.name = longName
                picked.append(long)
            }
            let choices = picked.map { exercise in
                SwapChoice(
                    replacing: workout.exercises[0].exerciseID,
                    exerciseID: exercise.id,
                    name: exercise.name,
                    replacement: SwapAlternatives.replacement(
                        of: workout.exercises[0], with: exercise, last: nil, units: .lb
                    )
                )
            }
            let state = SwapState(
                exerciseIndex: 0,
                exerciseID: workout.exercises[0].exerciseID,
                alternatives: .loaded(choices),
                alsoUpdateProgram: isOn
            )
            return WorkoutPresentation.swapSheet(state, in: workout, locale: Fixtures.locale)
        }

        static func view(_ model: SwapSheetModel) -> some View {
            SwapSheetFrame(model: model, send: { _ in }, content: {
                SwapSheetPage(model: model, send: { _ in })
            })
        }

        @Test("The sheet reads heading, Cancel, the line, the switch, then one stop per row", arguments: sizes)
        func tree_sheet(size: DynamicTypeSize) throws {
            let switchOff = try Self.view(Self.sheet()).accessibilityElements(SnapshotAppearance(.light, size))
            let switchOn = try Self.view(Self.sheet(isOn: true))
                .accessibilityElements(SnapshotAppearance(.light, size))
            let labels = switchOff.map(\.label)
            #expect(labels == [
                "Swap exercise", "Cancel", "Same movement pattern.", "Also update program",
                "Dumbbell Bench Press, Dumbbell · 15 lb, Use",
                "Weighted Dip, Bodyweight · 10 lb, Use",
                "Decline Push-Up, Bodyweight, Use"
            ], "\(size)")
            #expect(switchOff.count == 7 && switchOn.count == 7)
            guard switchOff.count == 7, switchOn.count == 7 else {
                return
            }
            #expect(switchOff.map(swapG2Kind) == [
                "heading",
                "button",
                "-",
                swapG2Kind(switchOff[3]),
                "button",
                "button",
                "button"
            ])
            #expect(!switchOff[3].value.isEmpty, "the switch says its state")
            #expect(
                switchOff[3].value != switchOn[3].value,
                "on and off read differently: \(switchOff[3].value) / \(switchOn[3].value)"
            )
        }

        @Test(
            "Every stop of the sheet is on the phone, none over another, buttons 44 pt, no word cut",
            arguments: sizes
        )
        func sheet_fitsAndNothingIsCut(size: DynamicTypeSize) throws {
            let model = try Self.sheet(isOn: true, longRow: true)
            let page = Self.view(model)
            // The title is `SheetChrome`'s (LedgerDesign), with its own font: not this module's to measure.
            var parts = [LayoutPart(model.line) { Text(model.line).ledgerFont(.bodyLight) }]
            for row in model.rows {
                parts.append(LayoutPart("\(row.name), \(row.detail), \(row.use)") {
                    HairlineRow(row.name, detail: row.detail, action: {}, accessory: {
                        Text(row.use).ledgerFont(.caption)
                    })
                })
            }
            for setting in LayoutSetting.everySetting(size) {
                let misplaced = WorkoutLayoutProbe.misplaced(in: page, setting)
                #expect(misplaced.isEmpty, "\(setting.testDescription): \(misplaced.joined(separator: "; "))")
                if !setting.isRightToLeft {
                    let cut = WorkoutLayoutProbe.cut(in: page, parts: parts, setting)
                    #expect(cut.isEmpty, "\(setting.testDescription): \(cut.joined(separator: "; "))")
                }
                for element in setting.elements(of: page) where element.traits.contains(.button) {
                    #expect(
                        element.frame.height >= 44 && element.frame.width >= 44,
                        "\(setting.testDescription): \"\(element.label)\" is \(element.frame.size)"
                    )
                }
            }
        }

        /// F10-S8b-G2-2: at `.xxxLarge`, a name that wraps puts "Swap exercise" before the title in VoiceOver's
        /// order (the button stands level with the place, above the title's first line).
        @Test(
            "FAILING (F10-S8b-G2-2): the card reads the title (heading), then Swap exercise (button, 44 pt)",
            arguments: sizes
        )
        func failing_card_titleRow(size: DynamicTypeSize) throws {
            for name in ["Barbell Bench Press", Self.longName] {
                let card = try Self.card(name: name)
                let view = ExerciseCard(model: card, send: { _ in })
                for setting in LayoutSetting.everySetting(size) {
                    let elements = setting.elements(of: view)
                    let titleIndex = elements.firstIndex { $0.label == name }
                    let swapIndex = elements.firstIndex { $0.label == "Swap exercise" }
                    guard let titleIndex, let swapIndex else {
                        Issue.record("\(setting.testDescription): title or button missing")
                        continue
                    }
                    let title = elements[titleIndex]
                    let swap = elements[swapIndex]
                    #expect(title.traits.contains(.header))
                    #expect(swap.traits.contains(.button))
                    #expect(
                        swapIndex == titleIndex + 1,
                        "\(setting.testDescription), \(name): the button follows the title; \(elements.map(\.label))"
                    )
                    #expect(swap.frame.height >= 44 && swap.frame.width >= 44, "\(setting.testDescription)")
                    let overlap = title.frame.intersection(swap.frame)
                    #expect(
                        overlap.isNull || overlap.width < 1 || overlap.height < 1,
                        "\(setting.testDescription): the title lies over the button"
                    )
                    // "Never under it": where the two share columns, the title does not start below the button.
                    let sharesColumns = title.frame.minX < swap.frame.maxX - 0.5
                        && swap.frame.minX < title.frame.maxX - 0.5
                    #expect(
                        !(sharesColumns && title.frame.minY >= swap.frame.maxY - 0.5),
                        "\(setting.testDescription), \(name): the title is under the button"
                    )
                    let misplaced = WorkoutLayoutProbe.misplaced(in: view, setting)
                    #expect(misplaced.isEmpty, "\(setting.testDescription): \(misplaced.joined(separator: "; "))")
                    if !setting.isRightToLeft {
                        let part = LayoutPart(name) { Text(name).ledgerFont(.heading) }
                        let cut = WorkoutLayoutProbe.cut(in: view, parts: [part], setting)
                        #expect(cut.isEmpty, "\(setting.testDescription): \(cut.joined(separator: "; "))")
                    }
                }
            }
        }
    }

    extension WorkoutSwapTreeAdversarialTests {
        /// The card's title row with a name that wraps.
        static func card(name: String) throws -> ExerciseCardModel {
            var workout = try SwapG2Catalog.workout()
            workout.exercises[0].name = name
            let screen = WorkoutPresentation.screen(
                .loaded(workout), isBusy: false, locale: Fixtures.locale, calendar: Fixtures.calendar
            )
            guard case let .workout(model) = screen else {
                throw SwapG2Refused()
            }
            return try #require(model.page.card)
        }
    }

    /// "heading", "button" or "-": what kind of stop VoiceOver says an element is.
    @MainActor
    func swapG2Kind(_ element: AccessibilityElementSnapshot) -> String {
        if element.traits.contains(.header) {
            return "heading"
        }
        if element.traits.contains(.button) {
            return "button"
        }
        return "-"
    }
#endif
