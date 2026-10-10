#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, gate G2, round 1, criteria 5, 6, 7, 10 and 12: the Day editor's VoiceOver tree against a tree
    /// written from the notes' tables and the model alone (`DayViewsOracle`), in the previews' states and in
    /// eight no preview draws, and what every stop sends: its model's action, once, and nothing where the
    /// model carries none. A control the model does not carry is a stop the oracle does not write, so a
    /// tree that matches has none.
    @Suite("Adversarial F11 S10 · trees and actions", .serialized, .tags(.feature))
    struct DayEditorViewsTreeAdversarialTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility5)
        ]

        @Test("Each of this tester's states reads the tree its model asks for", arguments: DayViewsState.allCases)
        func states_readTheirTrees(_ state: DayViewsState) throws {
            let model = try state.model()
            for appearance in Self.appearances {
                let difference = DayViewsProbe.difference(of: model, appearance)
                #expect(difference == nil, "\(appearance): \(difference ?? "")")
            }
            let mirrored = DayViewsProbe.difference(of: model, isRightToLeft: true)
            #expect(mirrored == nil, "right to left: \(mirrored ?? "")")
        }

        @Test(
            "Every stop sends its model's action once, a stepper its two; a heading, a text and the chosen chip none",
            arguments: DayViewsState.allCases
        )
        func states_everyStopSendsItsModelsAction(_ state: DayViewsState) throws {
            let model = try state.model()
            let wrong = DayViewsOracle.firstWrongSend(
                DayViewsProbe.sentByEachStop(of: model),
                DayViewsOracle.tree(model)
            )
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test(
            "Every stop of a preview sends its model's action once, at the largest text size too",
            arguments: ProgramPreview.dayEditors
        )
        func previews_everyStopSendsItsModelsAction(_ preview: ProgramPreview) throws {
            let model = try preview.dayEditorModel()
            let sent = DayViewsProbe.sentByEachStop(of: model, SnapshotAppearance(.dark, .accessibility5))
            let wrong = DayViewsOracle.firstWrongSend(sent, DayViewsOracle.tree(model))
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test("The states are the ones they are named for")
        func states_areWhatTheyAreNamedFor() throws {
            let empty = try DayViewsState.emptyDay.model()
            #expect(empty.groups.isEmpty && empty.deleteDay.confirmation.message == nil)
            let held = try #require(DayViewsState.heldWeek.model().openRow?.panel?.details)
            #expect(held.week.isHeld && !held.week.isDeload && held.week.eyebrow == "WEEK 4 · HELD")
            let unstored = try #require(DayViewsState.unstoredOpen.model().openRow)
            #expect(unstored.load == nil && unstored.panel?.details == nil && unstored.panel?.moveUp == nil)
            let deload = try #require(DayViewsState.deloadSupersetOpen.model().openRow)
            #expect(deload.index == "4A" && deload.panel?.details?.week.isDeload == true)
            let last = try #require(DayViewsState.lastOpen.model().openRow?.panel)
            #expect(last.moveDown == nil && last.moveUp != nil && last.supersetActions.map(\.title) == ["Break out"])
            let twelve = try DayViewsState.twelve.model()
            #expect(twelve.rows.count == 12 && twelve.groups.count == 10 && twelve.openRow?.index == "3C")
            #expect(twelve.openRow?.panel?
                .actionLine == "Break out · Superset with next · Move up · Move down · Remove")
            let digits = try #require(DayViewsState.fiveDigits.model().openRow)
            #expect(digits.load == "12,345.5 lb" && digits.panel?.details?.week.line == "3 × 10 @ 12,345.5 lb · RPE 8")
            #expect(digits.panel?.details?.strip.entries.allSatisfy { $0.text.contains(DayViewsState.load) } == true)
            let long = try DayViewsState.longWords.model()
            #expect(long.header.name == DayViewsState.longDay && long.supersetNotes == [DayViewsState.longNote])
        }
    }

    // MARK: - Opening each exercise in turn, the views in the loop

    extension DayEditorViewsTreeAdversarialTests {
        /// The stop of the row that reads `label`, activated once in `model`'s parts: what it sent.
        static func activating(_ label: String, in model: DayEditorModel.Content) -> [DayEditorAction] {
            var sent: [DayEditorAction] = []
            DayEditorParts(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityLabel == label {
                    _ = element.accessibilityActivate()
                }
            }
            return sent
        }

        /// Every exercise of a day is opened by its own row and closed by it again, a store between the taps
        /// (`DayScreen` applies an action as its documentation says); after each tap the parts read the tree
        /// of the next model: one row expanded with its panel under it, then none.
        @Test(
            "Each exercise in turn opens under its own row and closes again, the two of a superset too",
            arguments: [DayViewsState.lastOpen, .twelve, .unstoredOpen]
        )
        func rows_openAndCloseInTurn(_ state: DayViewsState) throws {
            var screen = try DayScreen(state.input())
            screen.input.openSlot = nil
            for label in try screen.content().rows.map(\.spokenLabel) {
                for opens in [true, false] {
                    let sent = try Self.activating(label, in: screen.content())
                    try #require(sent.count == 1, "\(label) sent \(sent.count) actions")
                    try screen.tap(sent.first)
                    let model = try screen.content()
                    #expect((model.openRow?.spokenLabel == label) == opens, "\(label), opening: \(opens)")
                    #expect(model.rows.count { $0.panel != nil } == (opens ? 1 : 0))
                    let difference = DayViewsProbe.difference(of: model)
                    #expect(difference == nil, "\(label), opening \(opens): \(difference ?? "")")
                }
            }
        }
    }

    // MARK: - Each string of the model: drawn, spoken, or neither

    extension DayEditorViewsTreeAdversarialTests {
        /// What a page draws, as something two drawings can be compared by.
        static func drawing(of model: DayEditorModel.Content) throws -> PixelBuffer {
            try ProgramDrawing.pixels(of: DayEditorParts(model: model), .dark)
        }

        /// Criterion 1 from the outside: every text on screen is a string of the model, and every string of
        /// the model is where the notes put it. Each string in turn is given another word; the drawing
        /// changes exactly when the notes say the string is drawn, and the tree exactly when they say it is
        /// spoken. A text a view left out, drew from the wrong field, or spoke from the drawn one fails here.
        @Test("Each string of the open double day is drawn where the notes draw it and spoken where they speak it")
        func everyString_isDrawnAndSpokenWhereTheNotesSay() throws {
            let model = try ProgramPreview.dayOpenDouble.dayEditorModel()
            let (drawn, read) = try (Self.drawing(of: model), DayEditorParts(model: model).stops())
            let paths = DayViewsText.paths(of: model)
            #expect(paths.count == 91, "\(paths.count) strings")
            for path in paths {
                let changed = DayViewsText.changing(path, to: "Qq", in: model)
                let isDrawn = try Self.drawing(of: changed) != drawn
                let isSpoken = DayEditorParts(model: changed).stops() != read
                let expected = DayViewsText.place(of: path)
                #expect(isDrawn == expected.isDrawn, "\(path) drawn: \(isDrawn)")
                #expect(isSpoken == expected.isSpoken, "\(path) spoken: \(isSpoken)")
            }
        }

        @Test("With every string of the model empty, no stop says a word of its own")
        func blankModel_saysNothing() throws {
            for preview in [ProgramPreview.dayOpenDouble, .dayDeload] {
                let stops = try DayEditorParts(model: DayViewsText.blank(preview.dayEditorModel())).stops()
                let words = stops.filter { !$0.label.isEmpty || !$0.hint.isEmpty || !["", "0", "1"].contains($0.value) }
                #expect(words.isEmpty, "\(words.prefix(3))")
            }
        }

        @Test("An empty name shows the model's placeholder, and the alert asks in the model's words")
        func placeholderAndAlert_areTheModels() throws {
            let model = try ProgramPreview.dayEditor.dayEditorModel()
            let words = DayViewsText(change: { path, text in
                [
                    "header.name": "",
                    "header.nameLabel": "Name of the day",
                    "confirm.title": "Drop it?",
                    "confirm.message": "Gone for good.",
                    "confirm.confirm": "Drop",
                    "confirm.cancel": "Keep"
                ][path] ?? text
            }).content(model)
            let hosted = ProgramTextFieldTests.Hosted(DayEditorHeader(model: words) { _ in })
            defer { hosted.close() }
            #expect(hosted.fields.map { [$0.placeholder ?? "", $0.text ?? ""] } == [["Name of the day", ""]])
            let kept = try DayEditorAccessibilityTests.asking(words.deleteDay, tapping: "Keep")
            #expect(kept.title == "Drop it?" && kept.message == "Gone for good.")
            #expect(kept.buttons == ["Drop 2", "Keep 1"])
            #expect(kept.sentByAsking.isEmpty && kept.sentByTheButton.isEmpty, "Cancel sends nothing")
            let dropped = try DayEditorAccessibilityTests.asking(words.deleteDay, tapping: "Drop")
            let isTheModels = dropped.sentByAsking.isEmpty && dropped
                .sentByTheButton == [model.deleteDay.confirmation.confirm.action]
            #expect(isTheModels, "\(dropped.sentByTheButton.count) actions")
        }
    }
#endif
