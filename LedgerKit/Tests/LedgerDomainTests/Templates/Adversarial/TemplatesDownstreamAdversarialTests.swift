import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: a generated block as the rest of the app reads it. `SessionBuilder`, `ProgressionRules`
/// and `TimeEstimate` run over all 32 inputs and are compared with spec §7.2, §7.3 and decision #14 worked out
/// by hand in `BriefTemplates+Rules` from the brief's tables and decision #21's loads.
@Suite("Adversarial F08 S1 · a generated block through the rules", .tags(.domain, .property))
struct TemplatesDownstreamAdversarialTests {
    typealias Brief = BriefTemplates

    static func settings(_ units: Units) -> Settings {
        var settings = Settings.default
        settings.units = units
        return settings
    }

    static func session(_ program: Program, week: Int, day: DayTemplate, units: Units) throws -> WorkoutState {
        try SessionBuilder.build(
            program: program,
            weekIndex: week,
            day: day,
            exercises: Brief.byID(Brief.catalog()),
            history: [:],
            settings: settings(units),
            id: WorkoutID(Fixtures.uuid(5000 + week)),
            device: Fixtures.deviceID,
            now: Fixtures.now
        )
    }

    /// `built` is `slot` in week `week`, as spec §7.2 and §7.3 work it out.
    static func check(_ built: WorkoutExercise, _ slot: Brief.ExpectedSlot, week: Int, input: Brief.Case) throws {
        let want = try Brief.prescription(slot, weekIndex: week, isDeload: week == 7, units: input.units)
        let load = Brief.weight(want.load, in: input.units)
        let label = "\(input), week \(week + 1), \(slot.exercise)"
        #expect(built.name == slot.exercise, "\(label)")
        #expect(built.targetLoad == load, "\(label): \(built.targetLoad.value(in: input.units)) for \(want.load)")
        #expect(built.targetSets == want.sets, "\(label)")
        #expect(built.targetReps == want.reps, "\(label)")
        #expect(built.rpe.value == want.rpe, "\(label)")
        #expect(built.rest.seconds == want.rest, "\(label)")
        #expect(built.step == Brief.weight(want.step, in: input.units), "\(label)")
        #expect(built.isSupersetWithPrevious == slot.superset, "\(label)")
        let working = built.sets.filter { $0.kind == .working }
        let drops = built.sets.filter { $0.kind == .drop }
        #expect(working.count == want.sets, "\(label)")
        #expect(working.allSatisfy { $0.weight == load && $0.reps.value == want.reps && !$0.isDone }, "\(label)")
        #expect(drops.count == slot.drop && built.sets.count == want.sets + slot.drop, "\(label)")
        let dropLoad = Brief.weight(Brief.reduced(want.load, step: want.step), in: input.units)
        #expect(drops.allSatisfy { $0.weight == dropLoad && $0.reps.value == want.reps }, "\(label)")
        #expect(slot.drop == 0 || built.sets.last?.kind == .drop, "\(label)")
        // ADR-007: everything a finished workout would store is a whole count of 10⁻⁷ g.
        #expect(throws: Never.self, "\(label)") {
            try ([built.targetLoad, built.step] + built.sets.map(\.weight)).forEach { try $0.checkStorable() }
        }
    }

    @Test(
        "SessionBuilder builds every day of every week with the spec's loads, sets, reps, RPE and rest",
        arguments: Brief.Case.all
    )
    func sessionBuilder_buildsEveryDayOfEveryWeek(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let expected = try Brief.expectedSlots(goal: input.goal, days: input.days)
        for week in 0 ..< 8 {
            for (day, slots) in zip(program.days, expected) {
                let session = try Self.session(program, week: week, day: day, units: input.units)
                #expect(session.isDeload == (week == 7), "\(input), week \(week + 1)")
                #expect(session.name == day.name && session.tag == day.tag, "\(input)")
                #expect(session.units == input.units && session.cursor == Cursor(exerciseIndex: 0, setIndex: 0))
                try #require(session.exercises.count == slots.count, "\(input): \(day.name)")
                #expect(session.exercises.map(\.slotID) == day.slots.map(\.id), "\(input): \(day.name)")
                for (built, slot) in zip(session.exercises, slots) {
                    try Self.check(built, slot, week: week, input: input)
                }
            }
        }
    }

    @Test("Spec §7.2's worked examples hold on the generated seed block, from decision #21's loads")
    func bothFourDay_workedExamples() throws {
        let input = Brief.Case(goal: .both, days: .four, units: .lb)
        let program = try Brief.program(input)
        func targets(_ day: Int, _ slot: Int, weeks: [Int]) throws -> [String] {
            try weeks.map { week in
                let built = try Self.session(program, week: week, day: program.days[day], units: .lb).exercises[slot]
                let load = built.targetLoad.formatted(in: .lb)
                return "\(built.targetSets)×\(built.targetReps) @ \(load) RPE \(built.rpe.label)"
            }
        }
        // Rule 10's shape (Incline DB Press 10–12, step 2.5) from 15 lb: 15×10, 15×11, 15×12, 17.5×10.
        #expect(try targets(0, 1, weeks: [0, 1, 2, 3]) == [
            "3×10 @ 15 RPE 8", "3×11 @ 15 RPE 8", "3×12 @ 15 RPE 8", "3×10 @ 17.5 RPE 8"
        ])
        // Rule 12's shape (Back Squat week 8) from 45 lb: 45 + 5 × 7 = 80 → 68 → 70 lb, 4 × 5 @ RPE 6.
        #expect(try targets(1, 0, weeks: [0, 6, 7]) == ["5×5 @ 45 RPE 8", "5×5 @ 75 RPE 8", "4×5 @ 70 RPE 6"])
        // Rule 11: the calf raise holds 20 lb; its deload is 17 → 17.5 lb on the machine's 2.5 lb step.
        #expect(try targets(1, 3, weeks: [0, 6, 7]) == ["4×12 @ 20 RPE 9", "4×12 @ 20 RPE 9", "3×12 @ 17.5 RPE 7"])
    }

    @Test(
        "ProgressionRules never leaves spec §7.1 over eight weeks, whatever weeks were missed",
        arguments: PropertySeed.all
    )
    func prescribe_withRandomMisses_staysInsideSpec71(seed: PropertySeed) throws {
        var random = seed.generator
        let input = Brief.Case.all[Int.random(in: 0 ..< Brief.Case.all.count, using: &random)]
        let program = try Brief.program(input)
        let exercises = try Brief.byID(Brief.catalog())
        for var slot in program.days.flatMap(\.slots) {
            slot.misses = Set((0 ..< 8).filter { _ in Bool.random(using: &random) })
            let exercise = try #require(exercises[slot.exerciseID])
            let start = try #require(slot.startLoad)
            for week in program.weeks {
                let asked = ProgressionRules.prescribe(
                    week: week, weekIndex: week.index, slot: slot, exercise: exercise, units: input.units
                )
                let missed = slot.misses.sorted()
                let label = "\(seed), \(input), \(exercise.name), week \(week.index + 1), misses \(missed)"
                #expect((1 ... 12).contains(asked.sets) && asked.sets >= slot.sets - 1, "\(label)")
                #expect((slot.reps ... slot.repsHi).contains(asked.reps), "\(label)")
                #expect((5 ... 10).contains(asked.rpe.value) && asked.rest == slot.rest, "\(label)")
                let steps = asked.load.grams / asked.step.grams
                #expect(steps > 0 && steps == decimalRounded(steps), "\(label): \(asked.load.value(in: input.units))")
                #expect(week.isDeload ? asked.load <= start.advanced(bySteps: 7, of: asked.step) : asked.load >= start)
                #expect(asked.step == exercise.equipment.defaultStep(in: input.units), "\(label)")
            }
        }
    }
}

// MARK: - Decision #24

extension TemplatesDownstreamAdversarialTests {
    @Test("Decision #24: a catalog refresh after the block is written changes no load in it", arguments: Units.allCases)
    func catalogRefresh_doesNotMoveTheBlock(units: Units) throws {
        let program = try Brief.program(Brief.Case(goal: .strength, days: .six, units: units))
        let exercises = try Brief.byID(Brief.catalog())
        for slot in program.days.flatMap(\.slots) {
            var refreshed = try #require(exercises[slot.exerciseID])
            let before = program.weeks.map { week in
                ProgressionRules.prescribe(
                    week: week, weekIndex: week.index, slot: slot, exercise: refreshed, units: units
                )
            }
            refreshed.defaultStartLoad = [.lb: .pounds(300), .kg: .kilograms(140)]
            let after = program.weeks.map { week in
                ProgressionRules.prescribe(
                    week: week, weekIndex: week.index, slot: slot, exercise: refreshed, units: units
                )
            }
            #expect(before == after, "\(refreshed.name)")
            #expect(before.first?.load == slot.startLoad, "\(refreshed.name)")
        }
    }
}

// MARK: - Time estimates and the calendar

extension TemplatesDownstreamAdversarialTests {
    @Test(
        "Decision #14: each day's estimate is the hand-worked one, in a normal week and in the deload",
        arguments: Brief.Case.pounds
    )
    func timeEstimate_matchesDecision14(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let exercises = try Brief.byID(Brief.catalog())
        let expected = try Brief.expectedSlots(goal: input.goal, days: input.days)
        let deload = try #require(program.weeks.last)
        for (day, slots) in zip(program.days, expected) {
            let normal = TimeEstimate.minutes(day: day, prescriptions: [:])
            #expect(normal == Brief.minutes(slots, sets: slots.map(\.scheme.sets)), "\(input): \(day.name)")
            let asked = try Dictionary(uniqueKeysWithValues: day.slots.map { slot in
                let exercise = try #require(exercises[slot.exerciseID])
                return (slot.id, ProgressionRules.prescribe(
                    week: deload, weekIndex: 7, slot: slot, exercise: exercise, units: input.units
                ))
            })
            let easy = TimeEstimate.minutes(day: day, prescriptions: asked)
            #expect(
                easy == Brief.minutes(slots, sets: slots.map { max(1, $0.scheme.sets - 1) }),
                "\(input): \(day.name)"
            )
            // The brief's tables give 18 to 57 minutes in a normal week and 11 to 43 in a deload.
            #expect((15 ... 60).contains(normal) && (10 ..< normal).contains(easy), "\(input): \(normal), \(easy)")
        }
    }

    @Test("Decision #14 by hand: Upper A, Lower A and Upper B of the seed block take 39, 38 and 37 minutes")
    func timeEstimate_seedDays() throws {
        let program = try Brief.program(Brief.Case(goal: .both, days: .four, units: .lb))
        // Upper A: 5 × 192 + 3 × 132 + 4 × 132, then three rounds of two sets and 75 s: 2,361 s.
        #expect(TimeEstimate.minutes(day: program.days[0], prescriptions: [:]) == 39)
        // Lower A: 5 × 222 + 3 × 162, then 7 sets over four rounds of 90 s: 2,250 s.
        #expect(TimeEstimate.minutes(day: program.days[1], prescriptions: [:]) == 38)
        // Upper B: 4 × 192 + 4 × 162 + 3 × 132, then the curl's 3 sets and a drop set at 102 s each: 2,220 s.
        #expect(TimeEstimate.minutes(day: program.days[2], prescriptions: [:]) == 37)
    }

    @Test(
        "On the calendar, each day of the eight weeks is the brief's training day or rest, for any week start",
        arguments: Weekday.allCases
    )
    func schedule_onTheCalendar_matchesTheBrief(weekStart: Weekday) throws {
        let start = try #require(ProgramTemplates.startDate(
            containing: Fixtures.now, weekStart: weekStart, calendar: Fixtures.calendar
        ))
        for input in Brief.Case.pounds {
            let program = try Brief.program(input, startDate: start)
            let weeks = WeekCalendar(startDate: program.startDate, weekStart: weekStart, calendar: Fixtures.calendar)
            for offset in 0 ..< 56 {
                let day = try #require(start.adding(days: offset))
                let noon = day.startOfDay(in: Fixtures.calendar).addingTimeInterval(12 * 3600)
                let position = Brief.expectedSchedule(input.days, weekIndex: offset / 7)[day.weekday]
                let label = "\(input), \(day) from a \(weekStart) start"
                #expect(weeks.scheduledDay(on: noon, in: program) == position.map { program.days[$0].id }, "\(label)")
                #expect(!weeks.isBlockComplete(program, on: noon), "\(label)")
            }
            let after = try #require(start.adding(days: 56)).startOfDay(in: Fixtures.calendar)
            #expect(weeks.isBlockComplete(program, on: after) && weeks.scheduledDay(on: after, in: program) == nil)
        }
    }
}
