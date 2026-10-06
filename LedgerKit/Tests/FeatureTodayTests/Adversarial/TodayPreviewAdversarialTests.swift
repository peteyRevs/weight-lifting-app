@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: the preview rows and the time estimate (S3 criteria 3, 6 and 12) against
/// `ProgressionRules.prescribe` and `TimeEstimate.minutes`, called here for every day of every week of the seed
/// program in both units, and by hand where a rule has a corner: a held load, a slot whose exercise is gone, a
/// program with no start loads of its own.
@Suite("Adversarial F09 S3 · preview rows and the time estimate", .tags(.feature))
nonisolated struct TodayPreviewAdversarialTests {
    typealias Support = TodayAdversarial

    /// The seed with its four days on Monday to Thursday of every week, so each day of each week can be today.
    static func fourDaysRunning() throws -> Program {
        var program = try Support.seed()
        let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday]
        for index in program.weeks.indices {
            program.weeks[index].schedule = Dictionary(uniqueKeysWithValues: zip(weekdays, program.days.map(\.id)))
        }
        return program
    }

    /// What the Domain prescribes for `day` in week `index`: each slot's prescription and the day's minutes.
    static func plan(
        _ program: Program,
        week index: Int,
        day: DayTemplate,
        units: Units
    ) throws -> (rows: [String], minutes: Int) {
        let catalog = try Support.exercises()
        let week = try #require(program.week(at: index))
        var prescriptions: [SlotID: Prescription] = [:]
        var rows: [String] = []
        for slot in day.slots {
            let exercise = try #require(catalog[slot.exerciseID])
            let asked = ProgressionRules.prescribe(
                week: week,
                weekIndex: index,
                slot: slot,
                exercise: exercise,
                units: units
            )
            prescriptions[slot.id] = asked
            let flags = (asked.isHeld ? " held" : "") + (asked.isDeload ? " deload" : "")
            rows.append("\(exercise.name): \(asked.sets) × \(asked.reps) @ \(asked.load.formatted(in: units))\(flags)")
        }
        return (rows, TimeEstimate.minutes(day: day, prescriptions: prescriptions))
    }

    static func shown(_ card: TodayModel.UpNext) -> [String] {
        card.rows.map { "\($0.name): \($0.scheme)\($0.isHeld ? " held" : "")\($0.isDeload ? " deload" : "")" }
    }

    @Test(
        "Every day of every week shows the Domain's prescription and estimate, in either unit",
        arguments: Units.allCases
    )
    func everyDayOfEveryWeek_showsTheDomainsPrescription(_ units: Units) throws {
        var program = try Self.fourDaysRunning()
        program.days[1].slots[0].misses = [1, 4]
        program.days[0].slots[1].misses = [0, 1, 2]
        var lines: [String] = []
        for index in 0 ..< 8 {
            for (offset, day) in program.days.enumerated() {
                let today = try #require(program.startDate.adding(days: index * 7 + offset))
                let input = try Support.input(program, now: Support.moment(today), settings: Support.settings(units))
                let card = try Support.upNext(TodayPresentation.make(input))
                let plan = try Self.plan(program, week: index, day: day, units: units)
                let deload = index == 7 ? " · Deload" : ""
                let meta = "Week \(index + 1) of 8\(deload) · ~\(plan.minutes) min"
                let route = TodayRoute.startWorkout(program: program.id, weekIndex: index, day: day.id)
                if Self.shown(card) != plan.rows || card.meta != meta || card.action.action.route != route {
                    lines.append("week \(index + 1) \(day.tag): \(card.meta ?? "nil") \(Self.shown(card).prefix(2))")
                }
            }
        }
        let agrees = lines.isEmpty
        #expect(agrees, "\(lines.count) of 32 days disagree:\n\(lines.prefix(4).joined(separator: "\n"))")
    }

    @Test("The off-schedule list estimates every day for the card's week, the deload week included")
    func offScheduleList_estimatesEveryDayOfEachWeek() throws {
        let program = try Support.seed()
        var lines: [String] = []
        for index in 0 ..< 8 {
            // Sunday is a rest day in every week of the seed.
            let today = try #require(program.startDate.adding(days: index * 7 + 6))
            let card = try Support.rest(TodayPresentation.make(Support.input(program, now: Support.moment(today))))
            let details = try program.days.map { day in
                let minutes = try Self.plan(program, week: index, day: day, units: .lb).minutes
                return "\(day.slots.count) exercises · ~\(minutes) min"
            }
            let shown = card.offSchedule.days.map(\.detail) + card.offSchedule.days.map(\.name)
            if shown != details + program.days.map(\.name) {
                lines.append("week \(index + 1): \(card.offSchedule.days.map(\.detail))")
            }
        }
        let agrees = lines.isEmpty
        #expect(agrees, "\(lines.count) of 8 weeks disagree:\n\(lines.prefix(3).joined(separator: "\n"))")
    }

    @Test("A load held after a missed week shows the held load and says so")
    func missedWeek_holdsTheLoad() throws {
        var program = try Support.seed()
        program.days[1].slots[0].misses = [0, 1]
        // Week 3 (index 2): no week advanced, the last one missed → 250, held. Week 4: one advanced → 255.
        let third = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 30)))
        let fourth = try Support.input(program, now: Support.moment(Support.civil(2026, 10, 7)))
        let held = try Support.upNext(TodayPresentation.make(third)).rows
        let moved = try Support.upNext(TodayPresentation.make(fourth)).rows
        #expect(held.first?.scheme == "5 × 5 @ 250")
        #expect(held.map(\.isHeld) == [true, false, false, false])
        #expect(moved.first?.scheme == "5 × 5 @ 255")
        #expect(moved.map(\.isHeld) == [false, false, false, false])
        // The others moved on: RDL 205 + 2×5, leg press 320 at 12 + 2 reps, calf raise fixed.
        #expect(held.dropFirst().map(\.scheme) == ["3 × 8 @ 215", "3 × 14 @ 320", "4 × 12 @ 160"])
    }

    @Test("A slot whose exercise is no longer stored has no row; the others keep theirs, in order", arguments: [1, 4])
    func slotWithoutItsExercise_hasNoRow(_ missing: Int) throws {
        let program = try Support.seed()
        var input = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 16)))
        let all = try Support.day("LA", in: program).slots.map(\.exerciseID)
        let gone = missing == 4 ? all : [Fixtures.CatalogID.romanianDeadlift]
        for id in gone {
            input.exercises[id] = nil
        }
        let model = TodayPresentation.make(input)
        let card = try Support.upNext(model)
        let names = missing == 4 ? [] : ["Back Squat", "Leg Press", "Standing Calf Raise"]
        #expect(card.rows.map(\.name) == names)
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.action.action.title == "Start workout")
        input.now = try Support.moment(Support.civil(2026, 9, 15))
        let detail = try Support.rest(TodayPresentation.make(input)).offSchedule.days[1].detail
        print("TodayPreviewAdversarialTests, \(missing) exercise(s) not stored: \(card.meta ?? "nil"); list: \(detail)")
    }

    @Test("A slot with no start load of its own starts from the catalog's, in the lifter's units")
    func slotWithoutAStartLoad_startsFromTheCatalog() throws {
        var program = try Support.seed()
        for index in program.days[1].slots.indices {
            program.days[1].slots[index].startLoad = nil
        }
        let now = try Support.moment(Support.civil(2026, 9, 30))
        // Week 3 (index 2). Pounds: squat 45 + 2×5, RDL 45 + 2×5, leg press 40 at 14 reps, calf raise 20.
        let pounds = try Support.upNext(TodayPresentation.make(Support.input(program, now: now))).rows
        #expect(pounds.map(\.scheme) == ["5 × 5 @ 55", "3 × 8 @ 55", "3 × 14 @ 40", "4 × 12 @ 20"])
        // Kilograms: squat 20 + 2×2.5, RDL 20 + 2×2.5, leg press 20 at 14 reps, calf raise 10.
        let kilograms = try Support.input(program, now: now, settings: Support.settings(.kg))
        let rows = try Support.upNext(TodayPresentation.make(kilograms)).rows
        #expect(rows.map(\.scheme) == ["5 × 5 @ 25", "3 × 8 @ 25", "3 × 14 @ 20", "4 × 12 @ 10"])
    }
}
