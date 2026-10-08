@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: stale and odd inputs (criteria 1, 3 and 9 of the slice; behaviours 13 and 19
/// of the plan): an open slot or a day that is gone, a day with no exercise or one, an exercise that is not
/// stored, misses, and the same input drawn twice. Seeds 1 to 30, and 1 to 60 for the misses.
@Suite("Adversarial F11 S6 · stale and odd inputs of the Day editor", .tags(.feature))
nonisolated struct DayEditorTotalityAdversarialTests {
    @Test("An open slot the day does not hold is read as none open, also one of another day")
    func openSlotNotHeld_isReadAsNoneOpen() throws {
        var input = try AdvDay.seed(day: 0)
        let closed = DayEditorPresentation.make(input)
        for stale in [SlotID(Fixtures.uuid(77)), input.program.days[1].slots[0].id] {
            input.openSlot = stale
            let isClosed = DayEditorPresentation.make(input) == closed
            #expect(isClosed)
            #expect(AdvDay.rows(input).allSatisfy { !$0.isOpen && $0.panel == nil && $0.action != .open(nil) })
        }
    }

    @Test("A day with no exercise draws its header, the library button and Delete day, and no row")
    func dayWithNoSlots_drawsItsHeaderAndNoRow() throws {
        let days = [AdvProgram.day(0), AdvProgram.day(1, name: "New day", tag: "D2")]
        let program = try AdvProgram.program(weeks: 3, days: days) { week, weekday in
            week == 1 && weekday == .friday ? 1 : nil
        }
        for week in [-1, 0, 2, 9] {
            let input = AdvDay.input(
                program,
                day: days[1].id,
                exercises: [:],
                week: week,
                open: SlotID(Fixtures.uuid(5))
            )
            let content = try #require(AdvDay.content(input))
            #expect(content.groups.isEmpty)
            #expect(content.header.position == "DAY 2 OF 2")
            #expect(content.header.name == "New day")
            #expect(content.header.tag == "D2")
            // The brief gives no meta line for a day with no exercise: the builder's "No exercises yet" after
            // the week (listed for Pete).
            #expect(content.header.meta == "Week \(Swift.min(Swift.max(week, 0), 2) + 1) · No exercises yet")
            #expect(content.addExercise.action == .openLibrary)
            #expect(content.deleteDay.confirmation.title == "Delete New day?")
            #expect(content.deleteDay.confirmation.message == "It's scheduled in 1 week. Those days become rest.")
        }
    }

    @Test("One exercise, one set reads 1 exercise · 1 set, and the minute is TimeEstimate's")
    func oneExerciseOneSet_readsTheSingularForms() throws {
        let slot = try AdvProgram.slot(1, exercise: 1, sets: 1, rest: 30)
        let day = AdvProgram.day(1, slots: [slot])
        let program = try AdvProgram.program(weeks: 2, days: [day], deloads: [1])
        let exercises = DayEditorModelAdversarialTests.exercises()
        let input = AdvDay.input(program, day: day.id, exercises: exercises, open: slot.id)
        #expect(AdvDay.content(input)?.header.meta == "Week 1 · 1 exercise · 1 set · ~1 min")
        #expect(AdvDay.content(input)?.header.position == "DAY 1 OF 1")
        #expect(AdvDay.rows(input).first?.scheme == "1×8")
        // A deload takes one set, never the last one (rule 12); 0 + 5 lb, × 0.85, to the 5 lb step is 5.
        var deload = input
        deload.weekIndex = 1
        #expect(AdvDay.content(deload)?.header.meta == "Week 2 · 1 exercise · 1 set · ~1 min")
        #expect(AdvDay.panel(deload)?.details?.week.line == "1 × 8 @ 5 lb · RPE 6")
        #expect(AdvDay.panel(deload)?.details?.strip.text == "W1 0 · W2 5 (deload)")
    }

    @Test("A slot whose exercise is not stored is listed under a dash, without a load, and can be removed")
    func slotOfAMissingExercise_isListedUnderADashAndRemovable() throws {
        let slots = try [
            AdvProgram.slot(0, exercise: 0), AdvProgram.slot(1, exercise: 99, sets: 4, rest: 150, drop: 1),
            AdvProgram.slot(2, exercise: 2, joined: true)
        ]
        let day = AdvProgram.day(1, slots: slots)
        let program = try AdvProgram.program(weeks: 3, days: [day], deloads: [2])
        let exercises = DayEditorModelAdversarialTests.exercises()
        let input = AdvDay.input(program, day: day.id, exercises: exercises, open: slots[1].id)
        let rows = AdvDay.rows(input)
        #expect(rows.map(\.index) == ["1", "2A", "2B"])
        #expect(rows[1].name == "—")
        #expect(rows[1].load == nil)
        #expect(rows[1].scheme == "4×8")
        #expect(rows[1].sub == "drop · RPE 8 · no rest")
        #expect(rows[1].spokenLabel == "2A, —")
        #expect(rows[1].spokenValue == "4×8 · drop · RPE 8 · no rest")
        #expect(AdvDay.content(input)?.header.meta == "Week 1 · 3 exercises · 11 sets · ~25 min")
        let panel = try #require(rows[1].panel)
        #expect(panel.details == nil)
        #expect(panel.supersetActions.isEmpty)
        #expect(panel.moveUp?.title == "Move up")
        #expect(panel.moveDown?.title == "Move down")
        #expect(AdvDay.slotEdit(of: panel.remove.action) == .remove(slot: slots[1].id))
        let removed = AdvDay.apply(panel.remove.action, to: input).input
        #expect(AdvDay.rows(removed).map(\.index) == ["1", "2"])
        #expect(AdvDay.rows(removed).allSatisfy { $0.name != "—" && $0.panel == nil })
        // With no exercise stored at all, every row is a dash and nothing traps.
        let bare = AdvDay.input(program, day: day.id, exercises: [:], week: 2, open: slots[2].id)
        #expect(AdvDay.rows(bare).map(\.name) == ["—", "—", "—"])
        #expect(AdvDay.rows(bare).map(\.load) == [nil, nil, nil])
        // Week 3 is a deload, and a row with no exercise has no prescription: it prints the slot's own sets
        // and RPE, not one set fewer and two points lower (finding F11-S6-3).
        #expect(AdvDay.rows(bare).map(\.scheme) == ["3×8", "4×8", "3×8"])
        #expect(AdvDay.rows(bare).map(\.sub) == ["RPE 8 · 1:30 rest", "drop · RPE 8 · no rest", "RPE 8 · 1:30 rest"])
        #expect(AdvDay.content(bare)?.header.meta == "Week 3 · 3 exercises · 11 sets · ~25 min")
        #expect(AdvDay.panel(bare)?.supersetActions.map(\.title) == ["Break out"])
    }
}

nonisolated extension DayEditorTotalityAdversarialTests {
    @Test(
        "Days that hold slots of exercises not stored are drawn for every week, unit and open slot, and stay themselves"
    )
    func seededDaysWithMissingExercises_areDrawnAndPure() throws {
        var wrong: [String] = []
        var drawn = 0
        let stored = AdvDay.stored()
        for seed in 1 ... 30 as ClosedRange<UInt64> {
            let (program, dayID) = try AdvDay.random(seed: seed, missing: true)
            let slots = program.days[1].slots
            for week in [-1, 0, program.weeks.count - 1, program.weeks.count] {
                for opened in [nil] + slots.map(\.id) {
                    let units: Units = week.isMultiple(of: 2) ? .lb : .kg
                    let input = AdvDay.input(
                        program, day: dayID, exercises: stored, units: units, week: week, open: opened
                    )
                    let model = DayEditorPresentation.make(input)
                    var more = input
                    more.exercises[AdvProgram.exercise(3).id] = AdvProgram.exercise(3)
                    let rows = AdvDay.rows(input)
                    let isRight = model == DayEditorPresentation.make(input)
                        && model == DayEditorPresentation.make(more)
                        && rows.map(\.id) == slots.map(\.id)
                        && rows.count { $0.panel != nil } == (opened == nil ? 0 : 1)
                        && zip(rows, slots).allSatisfy { ($0.load == nil) == (stored[$1.exerciseID] == nil) }
                        && rows.allSatisfy { ($0.name == "—") == ($0.load == nil) }
                    if !isRight {
                        wrong.append("seed \(seed) week \(week)")
                    }
                    drawn += 1
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
        #expect(drawn > 400)
    }

    @Test("A deload week that follows a missed week reads DELOAD alone, in the eyebrow and in the strip")
    func deloadWeekAfterAMiss_readsDeload() throws {
        var input = try AdvDay.seed(day: 1, week: 7, open: 0)
        input.program.days[1].slots[0].misses = [6]
        let details = try #require(AdvDay.panel(input)?.details)
        // 250 + 5 × 6 = 280, × 0.85 = 238, to the 5 lb step 240.
        #expect(details.week.line == "4 × 5 @ 240 lb · RPE 6")
        #expect(details.week.eyebrow == "WEEK 8 · DELOAD")
        #expect(details.strip.entries.last?.text == "W8 240 (deload)")
        // The Domain's prescription of this week is both a deload and held. The model's `isHeld` says what is
        // printed, not what the Domain says: false here (finding F11-S6-2).
        #expect(details.week.isDeload)
        #expect(details.week.isHeld == false)
        #expect(details.strip.entries.map(\.isHeld) == Array(repeating: false, count: 8))
    }

    @Test("Misses in any weeks: the strip's loads, flags and the eyebrow are the Domain's prescriptions")
    func misses_inAnyWeeks_areThePrescriptions() throws {
        var wrong: [String] = []
        for seed in 1 ... 60 as ClosedRange<UInt64> {
            var rng = SplitMix64(seed: seed)
            var input = try AdvDay.seed(day: Int(seed % 4), units: seed.isMultiple(of: 3) ? .kg : .lb, open: 0)
            let place = Int(seed % 4)
            input.weekIndex = Int.random(in: 0 ..< 8, using: &rng)
            input.program.days[place].slots[0].misses = Set((0 ..< 8).filter { _ in Int.random(
                in: 0 ... 2,
                using: &rng
            ) == 0 })
            let slot = input.program.days[place].slots[0]
            let exercise = try #require(input.exercises[slot.exerciseID])
            let weeks = ProgressionRules.prescriptions(
                for: slot, weeks: input.program.weeks, exercise: exercise, units: input.settings.units
            )
            let details = try #require(AdvDay.panel(input)?.details)
            let shown = weeks[input.weekIndex]
            let mark = shown.isDeload ? " · DELOAD" : (shown.isHeld ? " · HELD" : "")
            let prefixes = weeks.enumerated()
                .map { "W\($0.offset + 1) \($0.element.load.formatted(in: input.settings.units))" }
            let isRight = details.week.eyebrow == "WEEK \(input.weekIndex + 1)\(mark)"
                && details.strip.entries.map(\.isHeld) == weeks.map { $0.isHeld && !$0.isDeload }
                && details.strip.entries.map(\.isDeload) == weeks.map(\.isDeload)
                && zip(details.strip.entries, prefixes).allSatisfy { $0.text.hasPrefix($1) }
                && details.strip.text == details.strip.entries.map(\.text).joined(separator: " · ")
                && details.week.isHeld == (shown.isHeld && !shown.isDeload)
            if !isRight {
                wrong.append("seed \(seed): \(details.week.eyebrow) | \(details.strip.text)")
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(3))")
    }

    @Test("A week held and not a deload reads its load with (held) in the strip")
    func heldWeek_inTheStrip_readsHeld() throws {
        var input = try AdvDay.seed(day: 0, week: 0, open: 0)
        input.program.days[0].slots[0].misses = [0, 3]
        let strip = try #require(AdvDay.panel(input)?.details?.strip)
        // The brief gives "(deload)" for the strip and " · HELD" for the eyebrow only: "(held)" is listed for Pete.
        #expect(strip
            .text == "W1 180 · W2 180 (held) · W3 185 · W4 190 · W5 190 (held) · W6 195 · W7 200 · W8 175 (deload)")
    }

    @Test("Another locale changes no load, RPE or rest: they are the Domain's texts")
    func anotherLocale_keepsTheDomainsNumbers() throws {
        var input = try AdvDay.seed(day: 0, open: 1)
        let english = try #require(AdvDay.content(input))
        input.locale = Locale(identifier: "de_DE")
        let german = try #require(AdvDay.content(input))
        #expect(german.groups.flatMap(\.rows).map(\.load) == english.groups.flatMap(\.rows).map(\.load))
        #expect(german.groups.flatMap(\.rows).map(\.sub) == english.groups.flatMap(\.rows).map(\.sub))
        #expect(german.groups[1].rows[0].panel?.details?.strip.text == english.groups[1].rows[0].panel?.details?.strip
            .text)
        #expect(german.header.meta == english.header.meta)
    }
}
