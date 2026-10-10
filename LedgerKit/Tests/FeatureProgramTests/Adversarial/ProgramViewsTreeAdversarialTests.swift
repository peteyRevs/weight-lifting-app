#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, gate G2, round 1, criteria 1 and 6: the VoiceOver tree of states no preview draws, against a
    /// tree written from the notes' tables and the model alone (`ProgramViewsOracle`), and what every stop
    /// sends when it is activated: its model's action, once, and nothing where the model carries none.
    @Suite("Adversarial F11 S9 · trees and actions", .serialized, .tags(.feature))
    struct ProgramViewsTreeAdversarialTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility5)
        ]

        @Test(
            "The implementer's eight tables are the trees the oracle writes from the models",
            arguments: ProgramPreview.builders + ProgramPreview.libraries
        )
        func tables_areTheOraclesTrees(_ preview: ProgramPreview) throws {
            let table = try #require(ProgramTrees.byState[preview])
            let written: [ViewStop] =
                switch try preview.subject() {
                case let .builder(model): ProgramViewsOracle.builder(model).map(\.stop)
                case let .library(model): ProgramViewsOracle.library(model).map(\.stop)
                // S10: this oracle writes the builder's and the library's trees; the Day editor's states
                // are not among this test's arguments.
                case .dayEditor: throw ProgramPreview.NotThatScreen()
                }
            let difference = firstDifference(found: table, expected: written)
            #expect(difference == nil, "\(difference ?? "")")
        }

        @Test(
            "Each of this tester's builder states reads the tree its model asks for",
            arguments: BuilderState.allCases
        )
        func builder_states_readTheirTrees(_ state: BuilderState) throws {
            let model = try state.model()
            let expected = ProgramViewsOracle.builder(model).map(\.stop)
            for appearance in Self.appearances {
                let found = ProgramPage(model: model) { _ in }.stops(appearance)
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(appearance): \(difference ?? "")")
            }
            let mirrored = ProgramPage(model: model) { _ in }.environment(\.layoutDirection, .rightToLeft).stops()
            let difference = firstDifference(found: mirrored, expected: expected)
            #expect(difference == nil, "right to left: \(difference ?? "")")
        }

        @Test(
            "Each of this tester's library states reads the tree its model asks for",
            arguments: LibraryState.allCases
        )
        func library_states_readTheirTrees(_ state: LibraryState) throws {
            let model = try state.model()
            let expected = ProgramViewsOracle.library(model).map(\.stop)
            for appearance in Self.appearances {
                let found = ExercisePickerParts(model: model).stops(appearance)
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(appearance): \(difference ?? "")")
            }
        }

        @Test("The states are the ones they are named for")
        func states_areWhatTheyAreNamedFor() throws {
            let noDays = try BuilderState.noDays.model()
            #expect(noDays.days.cards.isEmpty && noDays.week.hint == nil && noDays.week.cells
                .allSatisfy { $0.action == nil })
            let twelve = try BuilderState.twelveExercises.model()
            #expect(twelve.days.cards.first?.meta.hasPrefix("12 exercises") == true)
            #expect(twelve.days.cards.first?.chips.count == 5 && twelve.days.cards.last?.chips.isEmpty == true)
            let ten = try BuilderState.tenDays.model()
            #expect(ten.week.cells.map(\.label) == ["D4", "D5", "D6", "D7", "D8", "D9", "D10"])
            let deloads = try BuilderState.sixteenDeloads.model()
            #expect(deloads.block.chips.count == 16 && deloads.block.chips.allSatisfy(\.isDeload))
            #expect(deloads.week.deload.isOn && deloads.week.applyToLater == nil)
            #expect(try BuilderState.loggedNotice.model().notice != nil)
            #expect(try LibraryState.everything.model().rows.count == 224)
            let picked = try LibraryState.everythingPicked.model()
            #expect(picked.rows.count == 224 && picked.rows.allSatisfy(\.isPicked) && picked.foot.action != nil)
            #expect(try LibraryState.emptyCatalog.model().empty != nil)
            let long = try LibraryState.longNames.model().rows.filter { $0.name.hasPrefix(LibraryState.exerciseName) }
            #expect(long.count == 2 && long.count { $0.isPicked } == 1)
            #expect(try LibraryState.longQuery.model().empty != nil)
        }
    }

    // MARK: - What each stop sends

    extension ProgramViewsTreeAdversarialTests {
        /// The first stop that did not send what the oracle says, as one line, or nil.
        nonisolated static func firstWrongSend<Action: Equatable & Sendable>(
            _ sent: [[Action]],
            _ expected: [ProgramViewsOracle.Expected<Action>]
        ) -> String? {
            guard sent.count == expected.count else {
                return "\(sent.count) stops were activated, \(expected.count) were expected"
            }
            for (place, pair) in zip(sent, expected).enumerated() where pair.0 != (pair.1.sends.map { [$0] } ?? []) {
                return "stop \(place + 1), \(pair.1.stop), sent \(pair.0.count) actions: \(pair.0)"
            }
            return nil
        }

        /// What each stop of a builder's page sends when it is activated, top to bottom.
        static func sentByEachStop(of model: ProgramBuilderModel) -> [[ProgramBuilderAction]] {
            var sent: [ProgramBuilderAction] = []
            return ProgramPage(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                elements.map { element in
                    let before = sent.count
                    _ = element.accessibilityActivate()
                    return Array(sent[before...])
                }
            }
        }

        static func sentByEachStop(of model: ExercisePickerModel) -> [[ExercisePickerAction]] {
            var sent: [ExercisePickerAction] = []
            return ExercisePickerParts(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                elements.map { element in
                    let before = sent.count
                    _ = element.accessibilityActivate()
                    return Array(sent[before...])
                }
            }
        }

        @Test(
            "Every stop of the builder sends its model's action once; a heading, a text and a dimmed pill send nothing",
            arguments: BuilderState.allCases
        )
        func builder_states_everyStopSendsItsModelsAction(_ state: BuilderState) throws {
            let model = try state.model()
            let wrong = Self.firstWrongSend(Self.sentByEachStop(of: model), ProgramViewsOracle.builder(model))
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test("Every stop of a builder preview sends its model's action once", arguments: ProgramPreview.builders)
        func builder_previews_everyStopSendsItsModelsAction(_ preview: ProgramPreview) throws {
            let model = try preview.builderModel()
            let wrong = Self.firstWrongSend(Self.sentByEachStop(of: model), ProgramViewsOracle.builder(model))
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test(
            "Every stop of the library sends its model's action once, all 224 rows too, and the dimmed foot nothing",
            arguments: LibraryState.allCases
        )
        func library_states_everyStopSendsItsModelsAction(_ state: LibraryState) throws {
            let model = try state.model()
            let wrong = Self.firstWrongSend(Self.sentByEachStop(of: model), ProgramViewsOracle.library(model))
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test(
            "The stepper sends plus on a swipe up and minus on a swipe down, in every state",
            arguments: BuilderState.allCases
        )
        func builder_states_stepperAdjusts(_ state: BuilderState) throws {
            let model = try state.model()
            var sent: [ProgramBuilderAction] = []
            ProgramPage(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.adjustable) {
                    element.accessibilityDecrement()
                    element.accessibilityIncrement()
                    element.accessibilityIncrement()
                }
            }
            let isSame = sent == [model.block.removeWeek, model.block.addWeek, model.block.addWeek]
            #expect(isSame, "\(sent.count) actions")
        }

        /// The review's N-8: the tests' parts copy the screen's `cancel`; this activates the real one. The
        /// reader is told to leave the scroll view out: only the pinned parts are read here.
        @Test("On the real sheet Cancel, the foot and VoiceOver's escape send the model's actions")
        func realSheet_pinnedParts_sendTheModelsActions() throws {
            let model = try ProgramPreview.libraryPicked.libraryModel()
            var sent: [ExercisePickerAction] = []
            let labels = ExercisePickerScreen(model: model) { sent.append($0) }
                .withAccessibilityElements(outsideScrollViews: true) { elements in
                    for element in elements where element.accessibilityTraits.contains(.button) {
                        _ = element.accessibilityActivate()
                    }
                    _ = elements.first?.accessibilityPerformEscape()
                    return elements.compactMap(\.accessibilityLabel)
                }
            #expect(labels == [model.title, model.cancel.title, model.foot.title])
            let isSame = try sent == [model.cancel.action, #require(model.foot.action), model.cancel.action]
            #expect(isSame, "\(sent)")
        }

        @Test("Right to left the strip's Monday stands at the right and the week chips run from the right")
        func rightToLeft_mirrorsTheRows() throws {
            let model = try ProgramPreview.builder.builderModel()
            let setting = ViewsSetting(isRightToLeft: true)
            let stops = ProgramViewsProbe.placed(ProgramPage(model: model) { _ in }, setting)
            let cells = ProgramViewsAlone.cells(of: model).map { stops[$0].frame.midX }
            #expect(cells == cells.sorted(by: >), "\(cells)")
            let chips = (3 ..< 7).map { stops[$0].frame.midX }
            #expect(chips == chips.sorted(by: >), "\(chips)")
        }
    }
#endif
