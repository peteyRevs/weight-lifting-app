#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, criteria 5, 6, 7, 10 and 12: what the Day editor's controls send, and what its tree says beyond
    /// the tables. The trees themselves (`DayEditorTrees`) are compared exactly by
    /// `ProgramAccessibilityTests.tree_isExactlyTheTable`, and the 44 pt targets by its
    /// `targets_areAtLeast44Points`, which run over every state of the preview registry.
    ///
    /// Read from the parts (`DayEditorParts`: the pinned header over the page), not from the screen, whose
    /// scroll view the hosted reader cannot see inside (testing-strategy §2.6).
    @Suite("Day editor accessibility", .serialized, .tags(.feature))
    struct DayEditorAccessibilityTests {
        /// What each stop of a model's parts must send, in reading order, from the model alone: a stepper is
        /// swiped down and then up, every other stop is activated. A heading, a text and the chosen
        /// progression send nothing; nor does "Delete day", which only asks.
        static func expected(_ model: DayEditorModel.Content) -> [[DayEditorAction]] {
            var sends: [[DayEditorAction]] = [[model.header.back.action], [model.header.done.action], [], []]
            for group in model.groups {
                sends += group.header == nil ? [] : [[]]
                for row in group.rows {
                    sends.append([row.action])
                    guard let panel = row.panel else {
                        continue
                    }
                    if let details = panel.details {
                        sends.append([])
                        sends += details.fields.map { [$0.decrement, $0.increment] }
                        sends.append([])
                        sends += details.progression.chips.map { $0.action.map { [$0] } ?? [] }
                        sends += [[], [details.dropSet.action]]
                    }
                    let controls = panel.supersetActions + [panel.moveUp, panel.moveDown, panel.remove]
                        .compactMap(\.self)
                    sends += controls.map { [$0.action] }
                    sends += panel.details == nil ? [] : [[]]
                }
            }
            return sends + [[model.addExercise.action], []]
        }

        /// What each stop of the parts sends, top to bottom.
        static func sentByEachStop(of model: DayEditorModel.Content) -> [[DayEditorAction]] {
            var sent: [DayEditorAction] = []
            return DayEditorParts(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                elements.map { element in
                    let before = sent.count
                    if element.accessibilityTraits.contains(.adjustable) {
                        element.accessibilityDecrement()
                        element.accessibilityIncrement()
                    } else {
                        _ = element.accessibilityActivate()
                    }
                    return Array(sent[before...])
                }
            }
        }

        /// The first stop that did not send what it must, as one line, or nil.
        static func firstWrongSend(_ sent: [[DayEditorAction]], _ expected: [[DayEditorAction]]) -> String? {
            guard sent.count == expected.count else {
                return "\(sent.count) stops were walked, \(expected.count) were expected"
            }
            for (place, pair) in zip(sent, expected).enumerated() where pair.0 != pair.1 {
                return "stop \(place + 1) sent \(pair.0.count) actions, \(pair.1.count) expected: \(pair.0)"
            }
            return nil
        }

        @Test(
            "Every control of the page and the header sends exactly its model's action, once, and nothing else does",
            arguments: ProgramPreview.dayEditors
        )
        func everyControl_sendsItsModelsAction_once(_ preview: ProgramPreview) throws {
            let model = try preview.dayEditorModel()
            let expected = Self.expected(model)
            #expect(expected.count == DayEditorTrees.byState[preview]?.count, "the walk and the table differ")
            let wrong = Self.firstWrongSend(Self.sentByEachStop(of: model), expected)
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test("The seed day's controls send what the brief says they do")
        func seedDay_sendsTheBriefsActions() throws {
            let day = try Fixtures.seedProgram().days[0]
            let bench = day.slots[0].id
            let model = try ProgramPreview.dayOpenLinear.dayEditorModel()
            let sent = Self.sentByEachStop(of: model)
            try #require(sent.count == DayEditorTrees.openLinear.count)
            #expect(sent[0] == [.route(.closeDay)] && sent[1] == [.route(.closeDay)], "Program and Done")
            #expect(sent[4] == [.open(nil)], "the open row closes its panel")
            // Sets, 5: down to 4, up to 6.
            #expect(sent[6] == [
                .edit(.slot(.set(.sets(4), slot: bench), day: day.id)),
                .edit(.slot(.set(.sets(6), slot: bench), day: day.id))
            ])
            #expect(sent[12] == [], "Linear is the chosen progression: no button")
            #expect(sent[13] == [.edit(.slot(.setProgression(.double, slot: bench), day: day.id))])
            #expect(sent[16] == [.edit(.slot(.setDropSet(true, slot: bench), day: day.id))])
            // "Superset with next" joins the next slot to this one, and closes the panel.
            #expect(sent[17] == [.edit(
                .slot(.setSuperset(true, slot: day.slots[1].id), day: day.id),
                closesPanel: true
            )])
            #expect(sent[18] == [.edit(.slot(.move(.downward, slot: bench), day: day.id))])
            #expect(sent[19] == [.edit(.slot(.remove(slot: bench), day: day.id), closesPanel: true)])
            #expect(sent[21] == [.open(day.slots[1].id)], "a closed row opens its panel")
            #expect(sent[sent.count - 2] == [.openLibrary])
            #expect(sent[sent.count - 1] == [], "Delete day asks first")
        }

        @Test("Headings are headings: the day's place, a superset, and the open exercise's progression")
        func headings_areTheSectionTitles() {
            let closed = ProgramParts(preview: .dayEditor).stops().filter { $0.kind == .heading }
            #expect(closed == [.heading("DAY 1 OF 4"), DayEditorTrees.superset])
            let open = ProgramParts(preview: .dayOpenLinear).stops().filter { $0.kind == .heading }.map(\.label)
            #expect(open == ["DAY 1 OF 4", "PROGRESSION", "Superset"])
        }

        @Test("A row says whether it is open, and only the open one has a panel under it")
        func rows_sayWhetherTheyAreOpen() {
            let stops = ProgramParts(preview: .dayOpenDouble).stops()
            let rows = stops.filter { $0.disclosure != .none }
            #expect(rows.map(\.disclosure) == [.collapsed, .expanded, .collapsed, .collapsed, .collapsed])
            #expect(rows.allSatisfy { $0.kind == .button })
            #expect(stops.count { $0.kind == .adjustable } == 6, "one panel's steppers")
            #expect(!ProgramParts(preview: .dayEditor).stops()
                .contains { $0.kind == .adjustable || $0.kind == .toggle })
        }

        @Test("The drop set is a switch of at least 44 points, on or off, with its note as the hint")
        func dropSet_isASwitch() {
            for (preview, expected) in [
                (ProgramPreview.dayOpenLinear, DayEditorTrees.dropSetOff), (.dayDropSet, DayEditorTrees.dropSetOn)
            ] {
                for appearance in ProgramAccessibilityTests.appearances {
                    let switches = ProgramParts(preview: preview).placedStops(appearance)
                        .filter { $0.stop.kind == .toggle }
                    #expect(switches.map(\.stop) == [expected], "\(preview.rawValue)")
                    #expect(switches.allSatisfy { $0.frame.height >= 44 - 0.001 && $0.frame.width >= 44 - 0.001 })
                }
            }
        }
    }

    // MARK: - What the model does not carry is not drawn

    extension DayEditorAccessibilityTests {
        @Test(
            "An exercise that is not stored has a panel of its actions alone: no week, stepper, chip, switch or strip"
        )
        func unstoredExercise_panelIsItsActions() throws {
            var input = try DayEditorFixtures.seedInput()
            let slot = try #require(input.program.days[0].slots.first)
            input.exercises[slot.exerciseID] = nil
            input.openSlot = slot.id
            let model = try DayEditorPresentation.make(input).content()
            #expect(model.openRow?.panel?.details == nil)
            let stops = DayEditorParts(model: model).stops()
            let panel = Array(stops.dropFirst(5).prefix(4))
            #expect(panel == [
                .button("Superset with next"), .button("Move down"), .button("Remove"),
                .row("2, Incline DB Press", value: "3×10 · 50 lb · Dumbbell · Reps 10–12 · RPE 8 · 1:30 rest")
            ])
            #expect(!stops.contains { $0.kind == .adjustable || $0.kind == .toggle || $0.label == "PROGRESSION" })
            let wrong = Self.firstWrongSend(Self.sentByEachStop(of: model), Self.expected(model))
            #expect(wrong == nil, "\(wrong ?? "")")
        }

        @Test("An exercise alone in its day has neither a superset action nor a move; a day with none has two buttons")
        func oneExercise_andNone() throws {
            var input = try DayEditorFixtures.input(slots: [DayEditorFixtures.slot(1)])
            input.openSlot = DayEditorFixtures.slotID(1)
            let one = try DayEditorPresentation.make(input).content()
            let labels = DayEditorParts(model: one).stops().filter { $0.kind == .button }.map(\.label)
            #expect(labels == [
                "Program", "Done", "1, Barbell Bench Press", "Double", "Fixed", "Remove",
                "+ Add exercise from library", "Delete day"
            ])
            let none = try DayEditorPresentation.make(DayEditorFixtures.input(slots: [])).content()
            #expect(DayEditorParts(model: none).stops() == DayEditorTrees.header(
                "DAY 1 OF 1", meta: "Week 1 · No exercises yet"
            ) + DayEditorTrees.foot)
        }
    }

    // MARK: - Delete day

    extension DayEditorAccessibilityTests {
        /// The alert "Delete day" presented, as UIKit holds it.
        struct Asked {
            var title = ""
            var message = ""
            /// Each button's title with its style: 1 cancels, 2 is destructive.
            var buttons: [String] = []
            /// What was sent before any button of the alert was tapped, and after the one asked for.
            var sentByAsking: [DayEditorAction] = []
            var sentByTheButton: [DayEditorAction] = []
        }

        /// Hosts the button, activates it, and taps the alert's button titled `tapping`. SwiftUI presents an
        /// alert as a `UIAlertController`; a test has no finger, so the button's handler is called as UIKit
        /// would call it (`handler` is UIKit's own name for it, read by key).
        static func asking(_ model: DayEditorModel.DeleteDay, tapping: String) throws -> Asked {
            typealias Handler = @convention(block) (UIAlertAction) -> Void
            var sent: [DayEditorAction] = []
            var asked = Asked()
            let alert: UIAlertController? = DeleteDayButton(model: model) { sent.append($0) }
                .withAccessibilityElements { elements in
                    for element in elements {
                        _ = element.accessibilityActivate()
                    }
                    // The alert is presented on the next turn of the run loop.
                    var view: UIView?
                    var container: Any? = elements.first
                    while let object = container as? NSObject, view == nil {
                        view = object as? UIView
                        container = object.value(forKey: "accessibilityContainer")
                    }
                    for _ in 0 ..< 5 where view?.window?.rootViewController?.presentedViewController == nil {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    }
                    let alert = view?.window?.rootViewController?.presentedViewController as? UIAlertController
                    asked.sentByAsking = sent
                    let action = alert?.actions.first { $0.title == tapping }
                    if let action, let handler = action.value(forKey: "handler") {
                        unsafeBitCast(handler as AnyObject, to: Handler.self)(action)
                    }
                    return alert
                }
            let presented = try #require(alert, "no alert was presented")
            asked.title = presented.title ?? ""
            asked.message = presented.message ?? ""
            asked.buttons = presented.actions.map { "\($0.title ?? "") \($0.style.rawValue)" }
            asked.sentByTheButton = Array(sent[asked.sentByAsking.count...])
            return asked
        }

        @Test("Delete day asks first, in the model's words; Cancel sends nothing and Delete the model's action")
        func deleteDay_asksFirst() throws {
            let model = try ProgramPreview.dayEditor.dayEditorModel().deleteDay
            let day = try Fixtures.seedProgram().days[0].id
            let cancelled = try Self.asking(model, tapping: "Cancel")
            #expect(cancelled.title == "Delete Upper A?")
            #expect(cancelled.message == "It's scheduled in 8 weeks. Those days become rest.")
            #expect(cancelled.buttons == ["Delete 2", "Cancel 1"], "Delete is destructive, Cancel cancels")
            #expect(cancelled.sentByAsking == [], "the button deletes nothing by itself")
            #expect(cancelled.sentByTheButton == [])
            let deleted = try Self.asking(model, tapping: "Delete")
            #expect(deleted.sentByAsking == [])
            #expect(deleted.sentByTheButton == [.edit(.deleteDay(day), closesPanel: true)])
            #expect(deleted.sentByTheButton == [model.confirmation.confirm.action])
        }

        @Test("For a day no week schedules the alert has no second line")
        func deleteDay_unscheduled_hasNoMessage() throws {
            let model = try DayEditorPresentation.make(DayEditorFixtures.input(slots: [])).content().deleteDay
            #expect(model.confirmation.message == nil)
            let asked = try Self.asking(model, tapping: "Cancel")
            #expect(asked.title == "Delete Arms?" && asked.message.isEmpty)
            #expect(asked.buttons == ["Delete 2", "Cancel 1"])
        }
    }
#endif
