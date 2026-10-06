import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Slice criterion 10: `ProgressionRules.prescriptions` is `prescribe` for each of the weeks given, each
/// under its own index. Checked against criterion 7's numbers, against `prescribe` called here, and against
/// spec §7.2 worked in whole numbers of 10⁻⁷ g, for every slot of the spec's seed program in both units.
@Suite("ProgressionRules.prescriptions (adversarial)", .tags(.domain, .property))
struct ProgressionPrescriptionsAdversarialTests {
    typealias Seed = LedgerFakes.Fixtures

    /// Eight weeks, the last a deload.
    static let weeks = (0 ..< 8).map { Fixtures.week($0, deload: $0 == 7) }

    /// The bundled catalog by id.
    static func catalogByID() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// `weight` as a count of 10⁻⁷ g, when it is a whole number of them.
    static func fine(_ weight: Weight) -> Int? {
        let count = NSDecimalNumber(decimal: weight.grams * 10_000_000).intValue
        return EditAdv.weight(fine: count) == weight ? count : nil
    }

    /// Spec §7.2 for one week, in whole numbers: the load in 10⁻⁷ g and the reps. A deload is × 0.85 to the
    /// nearest step, half a step going up (decision #3).
    static func expected(_ slot: Slot, start: Int, step: Int, week: Week) -> (load: Int, reps: Int) {
        let advancement = (0 ..< max(0, week.index)).count { !slot.misses.contains($0) }
        var load = start
        var reps = slot.reps
        switch slot.progression {
        case .linear:
            load = start + step * advancement
        case .double:
            let span = max(1, slot.repsHi - slot.reps + 1)
            load = start + step * (advancement / span)
            reps = slot.reps + advancement % span
        case .fixed:
            break
        }
        if week.isDeload {
            load = (170 * load + 100 * step) / (200 * step) * step
        }
        return (load, reps)
    }

    /// The whole prescription spec §7.2 asks for.
    static func prescription(_ slot: Slot, start: Int, step: Int, week: Week) throws -> Prescription {
        let numbers = expected(slot, start: start, step: step, week: week)
        return try Prescription(
            load: EditAdv.weight(fine: numbers.load),
            sets: week.isDeload ? max(1, slot.sets - 1) : slot.sets,
            reps: numbers.reps,
            rpe: Fixtures.rpe(week.isDeload ? max(5, slot.rpe.value - 2) : slot.rpe.value),
            rest: slot.rest,
            step: EditAdv.weight(fine: step),
            progression: slot.progression,
            isHeld: slot.misses.contains(week.index - 1),
            isDeload: week.isDeload
        )
    }
}

// MARK: - Criterion 7's numbers

extension ProgressionPrescriptionsAdversarialTests {
    @Test(
        "Criterion 7: Incline DB Press reads 50, 50, 50, 52.5, 52.5, 52.5, 55, 47.5 lb and reps 10 to 12 in turn."
    )
    func prescriptions_inclineDBPress_followsDoubleProgression() throws {
        let slot = try Fixtures.slot(Fixtures.inclineDB, id: 302, sets: 3, reps: 10, rest: 90, progression: .double)
        let rows = ProgressionRules.prescriptions(
            for: slot,
            weeks: Self.weeks,
            exercise: Fixtures.inclineDB,
            units: .lb
        )
        let loads = ["50", "50", "50", "52.5", "52.5", "52.5", "55", "47.5"].map(pounds)
        #expect(rows.map(\.load) == loads)
        #expect(rows.map(\.reps) == [10, 11, 12, 10, 11, 12, 10, 11])
        #expect(rows.map(\.sets) == [3, 3, 3, 3, 3, 3, 3, 2])
        #expect(rows.map(\.rpe.value) == [8, 8, 8, 8, 8, 8, 8, 6])
        #expect(rows.map(\.isDeload) == [false, false, false, false, false, false, false, true])
        #expect(rows.allSatisfy { !$0.isHeld && $0.step == .pounds(2.5) && $0.rest.seconds == 90 })
    }

    @Test("Criterion 7: Back Squat, 5 × 5 from 250 lb by 5, reads 240 lb in the deload week, 4 sets at RPE 6.")
    func prescriptions_backSquat_deloadWeekIs240() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 311, sets: 5, reps: 5, rest: 180)
        let rows = ProgressionRules.prescriptions(
            for: slot,
            weeks: Self.weeks,
            exercise: Fixtures.backSquat,
            units: .lb
        )
        #expect(rows.map(\.load) == ["250", "255", "260", "265", "270", "275", "280", "240"].map(pounds))
        #expect(rows.last?.sets == 4)
        #expect(rows.last?.rpe.value == 6)
        #expect(rows.last?.isDeload == true)
        #expect(rows.map(\.reps) == [5, 5, 5, 5, 5, 5, 5, 5])
    }

    @Test(
        "Criterion 7: with week 3 missed, the fourth week is held at week 3's load and later weeks run one step behind."
    )
    func prescriptions_missedWeek_marksTheNextAsHeld() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 311, sets: 5, reps: 5, rest: 180, misses: [2])
        let rows = ProgressionRules.prescriptions(
            for: slot,
            weeks: Self.weeks,
            exercise: Fixtures.backSquat,
            units: .lb
        )
        #expect(rows.map(\.isHeld) == [false, false, false, true, false, false, false, false])
        #expect(rows.map(\.load) == ["250", "255", "260", "260", "265", "270", "275", "240"].map(pounds))
    }

    @Test("The weeks are answered in the order given, each under its own index, however many and wherever they start.")
    func prescriptions_anyListOfWeeks_usesEachWeeksOwnIndex() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 311, sets: 5, reps: 5, rest: 180, misses: [4])
        func loads(_ weeks: [Week]) -> [Weight] {
            ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: Fixtures.backSquat, units: .lb)
                .map(\.load)
        }
        #expect(loads([]).isEmpty)
        #expect(loads(Array(Self.weeks[4...])) == ["270", "270", "275", "240"].map(pounds))
        #expect(loads([Self.weeks[6], Self.weeks[0], Self.weeks[3], Self.weeks[3]]) == ["275", "250", "265", "265"]
            .map(pounds))
        let held = ProgressionRules.prescriptions(
            for: slot, weeks: [Self.weeks[5], Self.weeks[4]], exercise: Fixtures.backSquat, units: .lb
        )
        #expect(held.map(\.isHeld) == [true, false])
    }
}

// MARK: - The seed program, both units

extension ProgressionPrescriptionsAdversarialTests {
    @Test(
        "Every slot of the seed program, seeded misses, both units: prescribe for each week, and spec §7.2.",
        arguments: PropertySeed.all.prefix(25)
    )
    func prescriptions_seedProgram_matchPrescribeAndTheSpec(seed: PropertySeed) throws {
        var generator = seed.generator
        let program = try Seed.seedProgram()
        let catalog = try Self.catalogByID()
        var tally = Tally()
        for var slot in program.days.flatMap(\.slots) {
            slot.misses = Set((0 ..< 8).filter { _ in Int.random(in: 0 ..< 4, using: &generator) == 0 })
            let exercise = try #require(catalog[slot.exerciseID])
            let start = try #require(slot.startLoad.flatMap(Self.fine))
            for units in Units.allCases {
                let step = EditAdv.fine(hundredths: EditAdv.defaultStepHundredths(exercise.equipment, units), units)
                let rows = ProgressionRules.prescriptions(
                    for: slot,
                    weeks: program.weeks,
                    exercise: exercise,
                    units: units
                )
                let viaPrescribe = program.weeks.map {
                    ProgressionRules.prescribe(
                        week: $0,
                        weekIndex: $0.index,
                        slot: slot,
                        exercise: exercise,
                        units: units
                    )
                }
                let bySpec = try program.weeks.map { try Self.prescription(slot, start: start, step: step, week: $0) }
                let note = "\(exercise.shortName) \(units) misses \(slot.misses.sorted())"
                tally.check(rows == viaPrescribe, "\(note): not prescribe for each week")
                tally.check(rows == bySpec, "\(note): loads \(rows.map { $0.load.formatted(in: units) })")
            }
        }
        #expect(tally.passed, "\(seed): \(tally.summary)")
        #expect(tally.cases == 16 * 2 * 2)
    }

    @Test(
        "The seed program's Back Squat reads 240 lb in week 8 and its Incline DB Press 50, 50, 50, 52.5."
    )
    func prescriptions_seedProgram_criterionSevenThroughTheCatalog() throws {
        let program = try Seed.seedProgram()
        let catalog = try Self.catalogByID()
        let squat = try #require(program.days[1].slots.first)
        let incline = try #require(program.days[0].slots.dropFirst().first)
        let squatRows = try ProgressionRules.prescriptions(
            for: squat, weeks: program.weeks, exercise: #require(catalog[squat.exerciseID]), units: .lb
        )
        #expect(squatRows.last?.load == .pounds(240))
        #expect(squatRows.last?.targetLine(units: .lb) == "4 × 5 @ 240 lb · RPE 6")
        let inclineRows = try ProgressionRules.prescriptions(
            for: incline, weeks: program.weeks, exercise: #require(catalog[incline.exerciseID]), units: .lb
        )
        #expect(inclineRows.map { $0.load.formatted(in: .lb) } == [
            "50",
            "50",
            "50",
            "52.5",
            "52.5",
            "52.5",
            "55",
            "47.5"
        ])
    }
}
