@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: every action the model offers, applied and drawn again (criteria 1, 4 and 10
/// of the slice; criteria 9 to 11 of the brief). An action is applied twice over: by the feature's
/// `applied(to:)` and by the Domain call the tester spells, and the two programs must be one. Seeds 1 to 40 for
/// the marks, 1 to 10 for the screens drawn again, 1 to 8 for the later programs.
@Suite("Adversarial F11 S6 · the Day editor's actions, applied and drawn again", .tags(.feature))
nonisolated struct DayEditorActionsAdversarialTests {
    static let seeds: ClosedRange<UInt64> = 1 ... 40

    /// Every seeded input with each of its slots open, and with none.
    static func inputs(missing: Bool = false) throws -> [(seed: UInt64, input: DayEditorInput)] {
        var found: [(UInt64, DayEditorInput)] = []
        for seed in seeds {
            let (program, dayID) = try AdvDay.random(seed: seed, missing: missing)
            let units: Units = seed.isMultiple(of: 2) ? .kg : .lb
            for opened in [nil] + program.days[1].slots.map(\.id) {
                found.append((seed, AdvDay.input(
                    program, day: dayID, exercises: AdvDay.stored(), units: units, week: Int(seed % 3), open: opened
                )))
            }
        }
        return found
    }

    @Test("Every action offered is one Domain call, and the screen drawn after it is the tester's screen of the result")
    func everyAction_appliedAndRedrawn_isTheTestersScreen() throws {
        var wrong: [String] = []
        var applied = 0
        for (seed, input) in try Self.inputs() where seed <= 10 {
            for (name, action) in AdvDay.actions(input) {
                let step = AdvDay.apply(action, to: input)
                if let edit = AdvDay.edit(of: action), edit.applied(to: input.program) != step.input.program {
                    wrong.append("seed \(seed) \(name): applied(to:) is not the Domain's call")
                }
                wrong += AdvDayScreen.differences(step.input).prefix(2).map { "seed \(seed) after \(name): \($0)" }
                applied += 1
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.count) wrong: \(wrong.prefix(4))")
        #expect(applied > 400)
    }

    /// What a slot edit is, for the counts: a move, a removal, a stepper's value, or another absolute edit.
    static func kind(of edit: SlotEdit?) -> String {
        switch edit {
        case .move: "move"
        case .remove: "remove"
        case .set: "stepper"
        default: "other"
        }
    }

    @Test("An action not marked relative gives, applied twice, what it gives once; a marked one is a move or a removal")
    func everyAction_appliedTwice_isOnceUnlessMarkedRelative() throws {
        var wrong: [String] = []
        var kinds: [String: Int] = [:]
        var movesThatDiffer = 0
        var removalsThatDiffer = 0
        for (seed, input) in try Self.inputs(missing: true) {
            for (name, action) in AdvDay.actions(input) {
                guard let edit = AdvDay.edit(of: action) else {
                    continue
                }
                let once = edit.applied(to: input.program)
                let differs = edit.applied(to: once) != once
                let slotEdit = AdvDay.slotEdit(of: action)
                let kind = Self.kind(of: slotEdit)
                let (isMove, isRemoval) = (kind == "move", kind == "remove")
                if edit.isRelative != (isMove || isRemoval) || slotEdit.map(\.isRelative) ?? false != edit.isRelative {
                    wrong.append("seed \(seed) \(name): marked relative \(edit.isRelative)")
                }
                if differs, !edit.isRelative {
                    wrong.append("seed \(seed) \(name): twice is not once")
                }
                // A stepper at its limit is offered and holds the value (the plan's behaviour 11); nothing else
                // that is offered may do nothing (criterion 4).
                if once == input.program, kind != "stepper" {
                    wrong.append("seed \(seed) \(name): offered, and changes nothing")
                }
                movesThatDiffer += isMove && differs ? 1 : 0
                removalsThatDiffer += isRemoval && differs ? 1 : 0
                kinds[edit.isRelative ? kind : "absolute", default: 0] += 1
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.count) wrong: \(wrong.prefix(4))")
        #expect(movesThatDiffer > 0)
        // A removal is marked relative (criterion 10) and yet gives, applied twice, what it gives once.
        #expect(removalsThatDiffer == 0)
        #expect((kinds["move"] ?? 0) > 50 && (kinds["remove"] ?? 0) > 50 && (kinds["absolute"] ?? 0) > 500)
    }

    @Test("Opening, closing, back, done and the library change nothing stored")
    func actionsThatAreNotEdits_storeNothing() throws {
        let input = try AdvDay.seed(day: 0, open: 3)
        let content = try #require(AdvDay.content(input))
        let rows = content.groups.flatMap(\.rows)
        #expect(rows.map(\.action) == [
            .open(rows[0].id), .open(rows[1].id), .open(rows[2].id), .open(nil), .open(rows[4].id)
        ])
        #expect(rows.map(\.isOpen) == [false, false, false, true, false])
        #expect(rows.map { $0.panel != nil } == [false, false, false, true, false])
        let other = AdvDay.apply(rows[4].action, to: input)
        #expect(other.edits == 0)
        #expect(AdvDay.rows(other.input).map(\.isOpen) == [false, false, false, false, true])
        #expect(AdvDay.apply(content.header.done.action, to: input).route == .closeDay)
        #expect(AdvDay.apply(content.header.back.action, to: input).route == .closeDay)
        #expect(AdvDay.apply(content.addExercise.action, to: input).opensLibrary)
    }
}

nonisolated extension DayEditorActionsAdversarialTests {
    @Test(
        "Criterion 9: Double on reps 8 with top 9 makes the top 10, the labels REP FLOOR and TOP OF RANGE, and the note"
    )
    func double_onRepsEightTopNine_widensToTenAndRelabels() throws {
        let slot = try Slot(
            id: SlotID(Fixtures.uuid(51000)), exerciseID: AdvDay.exercise(0).id, sets: 3, reps: 8, repsHi: 9,
            rpe: 8, restSeconds: 90, progression: .linear
        )
        let day = AdvProgram.day(1, slots: [slot])
        let program = try AdvProgram.program(weeks: 4, days: [day])
        var input = AdvDay.input(program, day: day.id, exercises: AdvDay.stored(), open: slot.id)
        var details = try #require(AdvDay.panel(input)?.details)
        #expect(details.fields.map(\.label) == ["SETS", "REPS", "START LOAD", "TARGET RPE", "REST"])
        #expect(details.progression.chips.map { $0.action == nil } == [true, false, false])
        let double = try #require(details.progression.chips[1].action)
        input = AdvDay.apply(double, to: input).input
        details = try #require(AdvDay.panel(input)?.details)
        #expect(details.fields.map(\.label) == [
            "SETS",
            "REP FLOOR",
            "TOP OF RANGE",
            "START LOAD",
            "TARGET RPE",
            "REST"
        ])
        #expect(details.fields.map(\.value) == ["3", "8", "10", "45 lb", "8", "1:30"])
        #expect(details.progression.note == "Adds a rep each week up to 10, then +5 lb back at 8.")
        #expect(details.progression.chips.map(\.isSelected) == [false, true, false])
        #expect(details.progression.chips.map { $0.action == nil } == [false, true, false])
        #expect(AdvDay.rows(input).first?.sub == "Barbell · Reps 8–10 · RPE 8 · 1:30 rest")
        // Away and back: the top is kept, hidden (behaviour 12), and choosing Double again widens nothing.
        input = AdvDay.apply(.edit(.slot(.set(.repsHi(9), slot: slot.id), day: day.id)), to: input).input
        let fixed = try #require(AdvDay.panel(input)?.details?.progression.chips[2].action)
        input = AdvDay.apply(fixed, to: input).input
        #expect(AdvDay.panel(input)?.details?.fields.map(\.label).contains("TOP OF RANGE") == false)
        let back = try #require(AdvDay.panel(input)?.details?.progression.chips[1].action)
        input = AdvDay.apply(back, to: input).input
        #expect(AdvDay.field(.repsHi, input)?.value == "10")
    }

    @Test("An action taken from one program and applied to a later one is the Domain's call on the later one")
    func actionFromAnEarlierProgram_appliedToALaterOne_isSafeAndDefined() throws {
        var wrong: [String] = []
        var applied = 0
        for (seed, input) in try Self.inputs(missing: true) where seed <= 8 {
            let day = try #require(AdvDay.day(input))
            var later: [Program] = [ProgramEditing.deleteDay(input.program, day: day.id)]
            for slot in day.slots {
                later.append(ProgramEditing.updateDay(input.program, day: day.id) {
                    DayEditing.removeSlot($0, slot: slot.id)
                })
                later.append(ProgramEditing.updateDay(input.program, day: day.id) {
                    DayEditing.move($0, slot: slot.id, .downward)
                })
            }
            for (name, action) in AdvDay.actions(input) {
                guard let edit = AdvDay.edit(of: action) else {
                    continue
                }
                for (place, program) in later.enumerated() {
                    let result = edit.applied(to: program)
                    let isDomain = result == AdvDay.edited(program, edit)
                    let keepsOtherDays = result.days.filter { $0.id != day.id } == program.days
                        .filter { $0.id != day.id }
                    let isGoneAndStays = place == 0 && result != program
                    if !isDomain || !keepsOtherDays || isGoneAndStays {
                        wrong.append("seed \(seed) \(name) on later program \(place)")
                    }
                    var redrawn = input
                    redrawn.program = result
                    _ = DayEditorPresentation.make(redrawn)
                    applied += 1
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.count) wrong: \(wrong.prefix(4))")
        #expect(applied > 800)
    }

    @Test("Deleting the day gives a model that says the day is gone, for any week and open slot")
    func deleteDay_confirmed_givesDayIsGone() throws {
        var input = try AdvDay.seed(day: 1, week: 7, open: 2)
        let confirm = try #require(AdvDay.content(input)?.deleteDay.confirmation.confirm.action)
        let step = AdvDay.apply(confirm, to: input)
        #expect(step.edits == 1)
        #expect(DayEditorPresentation.make(step.input) == .dayIsGone)
        #expect(step.input.program.days.count == 3)
        #expect(step.input.program.weeks.allSatisfy { !$0.schedule.values.contains(input.day) })
        input.day = DayTemplateID(Fixtures.uuid(99))
        #expect(DayEditorPresentation.make(input) == .dayIsGone)
        #expect(AdvDay.actions(input).isEmpty)
    }
}
