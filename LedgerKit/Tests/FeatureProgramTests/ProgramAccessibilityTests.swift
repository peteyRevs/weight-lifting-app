#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, criterion 6, and S10, criterion 10: the intended VoiceOver tree of each state of the three
    /// screens, pinned exactly (the stops, their order, labels, values, hints, and which are headings,
    /// selected, dimmed, expanded or collapsed), the 44 pt targets, and what each control of the builder and
    /// of the library sends (the Day editor's: `DayEditorAccessibilityTests`). Read through UIKit's
    /// accessibility tree, as VoiceOver reads it, at the default text size and at the largest of the snapshot
    /// matrix.
    ///
    /// The trees are read from the parts (`ProgramParts`), not from the screens: a screen puts its page in a
    /// scroll view, which the hosted reader cannot see inside (testing-strategy §2.6). The same stops inside
    /// the real scroll views are the nightly UI tests of S13 and S14.
    @Suite("Program accessibility", .serialized, .tags(.feature))
    struct ProgramAccessibilityTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility3)
        ]

        @Test(
            "Every state has exactly its intended VoiceOver tree, at the default and the largest text size",
            arguments: ProgramPreview.allCases
        )
        func tree_isExactlyTheTable(_ preview: ProgramPreview) throws {
            let expected = try #require(ProgramTrees.byState[preview], "no tree is written for this state")
            for appearance in Self.appearances {
                let found = ProgramParts(preview: preview).stops(appearance)
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test(
            "Every button and the block's stepper is a target of at least 44 by 44 points, at both text sizes",
            arguments: ProgramPreview.allCases
        )
        func targets_areAtLeast44Points(_ preview: ProgramPreview) throws {
            let expected = try #require(ProgramTrees.byState[preview])
                .count { $0.kind == .button || $0.kind == .adjustable }
            for appearance in Self.appearances {
                let targets = ProgramParts(preview: preview).placedStops(appearance)
                    .filter { $0.stop.kind == .button || $0.stop.kind == .adjustable }
                #expect(targets.count == expected)
                for target in targets {
                    // UIKit's conversion to window coordinates can report 44 pt as 43.999999999999886.
                    #expect(
                        target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                        "\(target.stop) at \(appearance): \(target.frame.size)"
                    )
                }
            }
        }

        @Test("Headings are headings: each screen's section titles, and nothing that can be tapped")
        func headings_areTheSectionTitles() {
            let builder = ProgramParts(preview: .deloadWeek).stops().filter { $0.kind == .heading }.map(\.label)
            #expect(builder == ["MY PROGRAM", "BLOCK · 8 WEEKS", "WEEK 8 · DELOAD", "TRAINING DAYS"])
            let library = ProgramParts(preview: .library).stops().filter { $0.kind == .heading }.map(\.label)
            #expect(library == ["Exercise library"])
        }
    }

    // MARK: - What the builder's controls send

    extension ProgramAccessibilityTests {
        /// What activating every button of a builder state, top to bottom, sends.
        static func sentByTheBuilder(_ preview: ProgramPreview) -> [ProgramBuilderAction] {
            var sent: [ProgramBuilderAction] = []
            ProgramParts(preview: preview, sendBuilder: { sent.append($0) }).withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            return sent
        }

        @Test(
            "Every button of the builder sends the action its model carries, once, and a disabled one nothing",
            arguments: ProgramPreview.builders
        )
        func builder_buttons_sendTheirModelsActions(_ preview: ProgramPreview) throws {
            let model = try preview.builderModel()
            let week = model.week
            let expected: [ProgramBuilderAction] = model.block.chips.map(\.action)
                + week.cells.compactMap(\.action)
                + [week.copyPrevious.action, week.applyToLater?.action, week.deload.action].compactMap(\.self)
                + model.days.cards.map(\.action)
                + [model.days.addDay.action].compactMap(\.self)
            let isSame = Self.sentByTheBuilder(preview) == expected
            #expect(isSame, "\(preview.rawValue)")
            #expect(expected.count == model.block.chips.count + 7 + model.days.cards.count
                + (week.copyPrevious.action == nil ? 0 : 1) + (week.applyToLater == nil ? 0 : 1) + 2)
        }

        @Test("The seed program's buttons send what the brief says they do")
        func builder_seedProgram_sendsTheBriefsActions() throws {
            let sent = Self.sentByTheBuilder(.builder)
            let days = try Fixtures.seedProgram().days.map(\.id)
            try #require(sent.count == 22, "8 weeks, 7 weekdays, 2 of the week's 3 actions, 4 days, and the add")
            #expect(Array(sent.prefix(8)) == (0 ..< 8).map { ProgramBuilderAction.selectWeek($0) })
            // Monday trains Upper A: a tap makes it Lower A. Tuesday rests: a tap makes it Upper A.
            #expect(sent[8] == .edit(.setSchedule(week: 0, weekday: .monday, day: days[1])))
            #expect(sent[9] == .edit(.setSchedule(week: 0, weekday: .tuesday, day: days[0])))
            #expect(sent[15] == .edit(.applyToLaterWeeks(week: 0)), "First week is disabled and sends nothing")
            #expect(sent[16] == .edit(.setDeload(true, week: 0)))
            #expect(sent[17] == .route(.day(days[0], weekIndex: 0)))
            #expect(sent.last == .addDay(name: "New day", weekIndex: 0))
        }

        @Test("The block's stepper is one adjustable element: up sends plus, down sends minus")
        func blockStepper_adjusts() throws {
            for preview in [ProgramPreview.builder, .twoWeeks] {
                let model = try preview.builderModel()
                var sent: [ProgramBuilderAction] = []
                ProgramParts(preview: preview, sendBuilder: { sent.append($0) }).withAccessibilityElements { elements in
                    let steppers = elements.filter { $0.accessibilityTraits.contains(.adjustable) }
                    #expect(steppers.count == 1)
                    steppers.first?.accessibilityIncrement()
                    steppers.first?.accessibilityDecrement()
                }
                #expect(sent == [model.block.addWeek, model.block.removeWeek], "\(preview.rawValue)")
            }
            // On two weeks, minus is not switched off: it sends the notice.
            #expect(try ProgramPreview.twoWeeks.builderModel().block.removeWeek == .notice(.minimumTwoWeeks))
        }

        @Test("In a program with no training day a weekday is read as text and offers nothing")
        func noDays_cellsAreText() throws {
            let program = try ProgramFixtures.program(weekCount: 2, days: [])
            let model = try ProgramPresentation.make(ProgramFixtures.input(program))
            var sent: [ProgramBuilderAction] = []
            let page = ProgramPage(model: model) { sent.append($0) }
            let stops = page.stops()
            #expect(stops.filter { $0.label == "Tuesday" } == [.text("Tuesday", value: "Rest")])
            #expect(!stops.contains { $0.label == "Tap to assign" || $0.hint == ProgramTrees.assignHint })
            #expect(!stops.contains { $0.label.contains("focus") }, "no day, no row")
            page.withAccessibilityElements { elements in
                for element in elements where element.accessibilityLabel == "Tuesday" {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.isEmpty)
        }
    }

    // MARK: - What the library's controls send

    extension ProgramAccessibilityTests {
        @Test(
            "Every button of the library sends the action its model carries, once, and the disabled foot nothing",
            arguments: ProgramPreview.libraries
        )
        func library_buttons_sendTheirModelsActions(_ preview: ProgramPreview) throws {
            let model = try preview.libraryModel()
            var sent: [ExercisePickerAction] = []
            let escaped = ProgramParts(preview: preview, sendLibrary: { sent.append($0) })
                .withAccessibilityElements { elements in
                    for element in elements where element.accessibilityTraits.contains(.button) {
                        _ = element.accessibilityActivate()
                    }
                    return elements.first?.accessibilityPerformEscape() ?? false
                }
            let expected: [ExercisePickerAction] = [model.cancel.action]
                + model.muscles.chips.map(\.action) + model.equipment.chips.map(\.action)
                + model.rows.map(\.action) + [model.empty?.clear.action, model.foot.action].compactMap(\.self)
                + [model.cancel.action]
            let isSame = sent == expected
            #expect(isSame, "\(preview.rawValue)")
            #expect(escaped, "VoiceOver's escape gesture cancels, as the button does")
        }

        @Test("The picked library's buttons send what the brief says they do")
        func library_picked_sendsTheBriefsActions() throws {
            let model = try ProgramPreview.libraryPicked.libraryModel()
            #expect(model.cancel.action == .cancel)
            #expect(model.muscles.chips[1].action == .setMuscle(.chest))
            #expect(model.equipment.chips[0].action == .setEquipment(nil))
            // A picked row takes itself out; one that is not picked goes in.
            #expect(model.rows[0].action == .setPicked(false, exercise: model.rows[0].id))
            #expect(model.rows[2].action == .setPicked(true, exercise: model.rows[2].id))
            #expect(model.foot.action == .add([model.rows[1].id, model.rows[3].id, model.rows[0].id]))
            #expect(try ProgramPreview.libraryNothing.libraryModel().empty?.clear.action == .clearFilters)
        }
    }
#endif
