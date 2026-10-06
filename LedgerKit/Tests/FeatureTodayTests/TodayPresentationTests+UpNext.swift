@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Up-next card for today's session (specification criterion 3; the body's criteria 1 and 6).
nonisolated extension TodayPresentationTests {
    /// The prescriptions `ProgressionRules` gives day `dayIndex` of `program` in week `weekIndex`, by slot.
    static func prescriptions(
        of program: Program,
        weekIndex: Int,
        dayIndex: Int,
        units: Units = .lb
    ) throws -> [SlotID: Prescription] {
        let exercises = try TodayFixtures.exercises()
        let week = try #require(program.week(at: weekIndex))
        var prescriptions: [SlotID: Prescription] = [:]
        for slot in program.days[dayIndex].slots {
            prescriptions[slot.id] = try ProgressionRules.prescribe(
                week: week,
                weekIndex: weekIndex,
                slot: slot,
                exercise: #require(exercises[slot.exerciseID]),
                units: units
            )
        }
        return prescriptions
    }

    @Test("Week 1's Wednesday is Lower A with its four exercises and Start workout (criterion 1)")
    func upNext_weekOneWednesday_isLowerAWithFourRows() throws {
        let program = try TodayFixtures.program()
        let card = try #require(TodayPresentation.make(TodayFixtures.input(program: program)).card.upNext)
        #expect(card.eyebrow == "UP NEXT")
        #expect(card.meta == "Week 1 of 8 · ~38 min")
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.rows.map(\.name) == ["Back Squat", "Romanian Deadlift", "Leg Press", "Standing Calf Raise"])
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 250", "3 × 8 @ 205", "3 × 12 @ 320", "4 × 12 @ 160"])
        #expect(card.rows.allSatisfy { !$0.isHeld && !$0.isDeload })
        let route = TodayRoute.startWorkout(
            program: program.id,
            weekIndex: 0,
            day: program.days[TodayFixtures.DayIndex.lowerA].id
        )
        #expect(card.action == .start(TodayModel.Action(title: "Start workout", route: route)))
    }

    @Test("Each row is what ProgressionRules prescribes for that week: sets, reps and the load", arguments: 0 ..< 8)
    func upNext_everyWeek_rowsAreTheWeeksPrescriptions(weekIndex: Int) throws {
        let program = try TodayFixtures.program()
        // Wednesday of week `weekIndex`, at noon.
        let now = Fixtures.date(2026, 9, 16, hour: 12).addingTimeInterval(Double(weekIndex) * 7 * 86400)
        let card = try #require(TodayPresentation.make(TodayFixtures.input(program: program, now: now)).card.upNext)
        let day = program.days[TodayFixtures.DayIndex.lowerA]
        let prescribed = try Self.prescriptions(
            of: program,
            weekIndex: weekIndex,
            dayIndex: TodayFixtures.DayIndex.lowerA
        )
        let expected = try day.slots.map { slot in
            let prescription = try #require(prescribed[slot.id])
            return "\(prescription.sets) × \(prescription.reps) @ \(prescription.load.formatted(in: .lb))"
        }
        #expect(card.rows.map(\.scheme) == expected)
        #expect(card.action.action.route == .startWorkout(program: program.id, weekIndex: weekIndex, day: day.id))
    }

    @Test("The minutes are decision #14's estimate for the week's prescriptions")
    func upNext_minutes_areTimeEstimateMinutes() throws {
        let program = try TodayFixtures.program()
        let lowerA = TodayFixtures.DayIndex.lowerA
        let prescribed = try Self.prescriptions(of: program, weekIndex: 0, dayIndex: lowerA)
        let minutes = TimeEstimate.minutes(day: program.days[lowerA], prescriptions: prescribed)
        // 15 sets of 42 s; rest after 5 squats (180 s), 3 deadlifts (120 s) and 4 superset rounds (90 s).
        #expect(minutes == 38)
        let card = try #require(TodayPresentation.make(TodayFixtures.input(program: program)).card.upNext)
        #expect(card.meta == "Week 1 of 8 · ~\(minutes) min")
    }

    @Test("In the deload week the meta says so and the rows are the deload prescription (criterion 6)")
    func upNext_deloadWeek_metaAndLoads() throws {
        let program = try TodayFixtures.program()
        // Wednesday of week 8.
        let input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 11, 4, hour: 9))
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.meta == "Week 8 of 8 · Deload · ~28 min")
        // Testing strategy §2.1: the squat's 285 lb becomes 240 lb, four sets of five.
        #expect(card.rows.map(\.scheme) == ["4 × 5 @ 240", "2 × 8 @ 205", "2 × 13 @ 277.5", "3 × 12 @ 135"])
        #expect(card.rows.map(\.isDeload) == [true, true, true, true])
        let lowerA = TodayFixtures.DayIndex.lowerA
        let prescribed = try Self.prescriptions(of: program, weekIndex: 7, dayIndex: lowerA)
        #expect(TimeEstimate.minutes(day: program.days[lowerA], prescriptions: prescribed) == 28)
    }

    @Test("In kilograms the loads are the kilogram prescription, with no unit after them")
    func upNext_kilograms_loadsAreInKilograms() throws {
        let program = try TodayFixtures.program()
        let input = try TodayFixtures.input(program: program, settings: Fixtures.settingsKg)
        let card = try #require(TodayPresentation.make(input).card.upNext)
        let prescribed = try Self.prescriptions(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            units: .kg
        )
        let expected = try program.days[TodayFixtures.DayIndex.lowerA].slots.map { slot in
            let prescription = try #require(prescribed[slot.id])
            return "\(prescription.sets) × \(prescription.reps) @ \(prescription.load.formatted(in: .kg))"
        }
        #expect(card.rows.map(\.scheme) == expected)
        // 250 lb is 113.398 kg: a converted load prints to one decimal.
        #expect(card.rows.first?.scheme == "5 × 5 @ 113.4")
    }

    @Test("A week whose load was held says so on its row")
    func upNext_missedLastWeek_rowIsHeld() throws {
        var program = try TodayFixtures.program()
        program.days[TodayFixtures.DayIndex.lowerA].slots[0].misses = [0]
        // Wednesday of week 2: week 1's squat was missed, so 250 lb holds.
        let input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 23, hour: 9))
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.rows.map(\.isHeld) == [true, false, false, false])
        #expect(card.rows.first?.scheme == "5 × 5 @ 250")
    }

    @Test("A slot whose exercise is no longer stored has no row; the estimate keeps the slot's own values")
    func upNext_missingExercise_rowIsOmitted() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        input.exercises[Fixtures.CatalogID.romanianDeadlift] = nil
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.rows.map(\.name) == ["Back Squat", "Leg Press", "Standing Calf Raise"])
        #expect(card.meta == "Week 1 of 8 · ~38 min")
        input.exercises = [:]
        let empty = try #require(TodayPresentation.make(input).card.upNext)
        #expect(empty.rows.isEmpty)
        #expect(empty.title == "Lower A — Squat focus")
    }

    @Test("A day that holds a slot's id twice is drawn all the same")
    func upNext_slotIDTwice_doesNotTrap() throws {
        var program = try TodayFixtures.program()
        let slots = program.days[TodayFixtures.DayIndex.lowerA].slots
        program.days[TodayFixtures.DayIndex.lowerA].slots = slots + [slots[0]]
        let card = try #require(TodayPresentation.make(TodayFixtures.input(program: program)).card.upNext)
        #expect(card.rows.count == 5)
    }
}
