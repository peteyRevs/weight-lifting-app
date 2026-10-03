import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: what `materialize` stores at the edges of its values: exact e1RMs and totals
/// (ADR-007), weights and reps at the ends of their columns, dates at the ends of `Double`, hostile text, and
/// states that are not finished.
@Suite("Adversarial S3 · stored values", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutValuesAdversarialTests {
    /// The count of 10⁻⁷ g in `pounds` lb, by integer arithmetic: a pound is 4,535,923,700 units.
    static func units(hundredthsOfAPound: Int64) -> Int64 {
        hundredthsOfAPound * 45_359_237
    }

    /// Brzycki in integers: `units × 36 / (37 − reps)` grams, rounded half away from zero, as units.
    static func estimate(units: Int64, reps: Int64) -> Int64 {
        let numerator = units * 36
        let denominator = (37 - reps) * 10_000_000
        return (2 * numerator + denominator) / (2 * denominator) * 10_000_000
    }

    @Test("Every done set's e1RM column is Brzycki rounded to the gram, by integer arithmetic; 13 reps store NULL")
    func e1RM_matchesTheIntegerOracle() async throws {
        let stack = try await S3Kit.stack()
        let hundredths: [Int64] = [0, 1, 250, 4500, 18500, 22575, 31499, 100_000]
        var rows: [S3Kit.RowSpec] = []
        for reps in 1 ... 13 {
            rows.append(S3Kit.RowSpec(S3Kit.bench, hundredths.map { value in
                S3Kit.set(Decimal(value) / 100, reps, SetKind.allCases[Int(value) % 4])
            }))
        }
        try await stack.materialize(S3Kit.workout(1, rows))
        let stored = try await stack.queue.read { database in
            try Row.fetchAll(database, sql: "SELECT weight_e7g, reps, e1rm_e7g FROM logged_set").map { row in
                (weight: row["weight_e7g"] as Int64, reps: row["reps"] as Int64, estimate: row["e1rm_e7g"] as Int64?)
            }
        }
        #expect(stored.count == 13 * hundredths.count)
        for row in stored {
            let expected: Int64? = row.reps > 12 ? nil : Self.estimate(units: row.weight, reps: row.reps)
            #expect(row.estimate == expected, "\(row.weight) units × \(row.reps)")
        }
        #expect(Set(stored.map(\.weight)) == Set(hundredths.map(Self.units)))
    }

    @Test("Weights at both ends of the column, one unit, zero, and reps at Int32's end read back equal")
    func extremeWeightsAndReps_roundTrip() async throws {
        let stack = try await S3Kit.stack()
        var workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, Array(repeating: S3Kit.set(1, 1), count: 6))])
        let weights = [Int64.max, .min, 1, -1, 0, 4_535_923_700].map(Weight.init(e7g:))
        for (index, weight) in weights.enumerated() {
            workout.exercises[0].sets[index].weight = weight
            workout.exercises[0].sets[index].doneAt = nil // undone: no estimate or volume beyond the column
        }
        workout.exercises[0].sets[4].reps = Reps(clamping: Int(Int32.max))
        workout.exercises[0].sets[4].doneAt = S3Kit.now // 0 g × 2³¹ reps is a volume of 0
        workout.exercises[0].targetLoad = Weight(e7g: .max)
        workout.exercises[0].step = Weight(e7g: 1)
        workout.exercises[0].targetSets = Int(Int32.max)
        workout.exercises[0].targetReps = Int(Int32.min)
        try await stack.materialize(workout)
        #expect(try await stack.workouts.workout(id: workout.id) == workout)
        #expect(try await stack.stats().bestE1RM(exerciseID: S3Kit.bench) == nil)
    }

    @Test("A weight, an estimate or a volume that does not fit its column is refused; nothing is stored", arguments: [
        "⅛ lb", "10⁻⁸ g", "an estimate beyond Int64", "a volume beyond Int64", "NaN"
    ])
    func valuesBeyondTheColumn_areRefused(value: String) async throws {
        let stack = try await S3Kit.stack()
        let stored = S3Kit.mixed(1)
        try await stack.materialize(stored)
        var workout = S3Kit.mixed(1)
        switch value {
        case "⅛ lb": workout.exercises[1].sets[2].weight = .pounds(0.125)
        case "10⁻⁸ g": workout.exercises[0].step = Weight(grams: Decimal(sign: .plus, exponent: -8, significand: 1))
        case "an estimate beyond Int64": workout.exercises[0].sets[0].weight = Weight(e7g: .max - 807) // × 36 / 32
        case "a volume beyond Int64": workout.exercises[1].sets[1].reps = Reps(clamping: Int(Int32.max))
        default: workout.exercises[1].sets[0].weight = Weight(grams: .nan)
        }
        stack.clock.advance()
        let before = try await stack.dump()
        await #expect("\(value) was stored") { try await stack.materialize(workout) } throws: { error in
            if case .inexactWeight = error as? LedgerPersistenceError {
                true
            } else {
                false
            }
        }
        #expect(try await stack.dump() == before)
        #expect(try await stack.workouts.workout(id: stored.id) == stored)
    }

    @Test("Dates at the ends of Double, before 2001 and with every bit of a fraction read back exactly", arguments: [
        1e300, -1e300, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude,
        -0.0, 811_228_800.493_826_8, -63_114_076_800.000_001, 4_611_686_018_427_387_904.0
    ])
    func extremeDates_roundTripAndTrapNoQuery(seconds: Double) async throws {
        let stack = try await S3Kit.stack()
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        // The extreme date is the start, the date every list and query reads (product decision #26), and the
        // mirrored one the end, so both columns still hold every extreme.
        var workout = S3Kit.mixed(1, endedAt: Date(timeIntervalSinceReferenceDate: -seconds))
        workout.startedAt = date
        let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: workout, at: date)
        try await stack.materialize(workout, prs: [record])
        let read = try #require(try await stack.workouts.workout(id: workout.id))
        #expect(read == workout)
        #expect(read.startedAt.timeIntervalSinceReferenceDate.bitPattern == (seconds + 0).bitPattern)
        #expect(try await stack.workouts.recent(limit: 1) == [workout])
        let forever = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(try await stack.workouts.workouts(in: date ..< forever) == [workout])
        #expect(try await stack.stats()
            .sessionsCompleted(in: Date(timeIntervalSinceReferenceDate: -.infinity) ..< date) == 0)
        // No stats query traps on it, whatever the calendar makes of the date.
        let stats = stack.stats(now: date)
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench)?.date == date)
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == [record])
        for zone in ["UTC", "Pacific/Apia", "America/St_Johns"] {
            let weeks = try await stats.e1RMByWeek(
                exerciseID: S3Kit.bench,
                lastWeeks: .max,
                calendar: S3Kit.calendar(zone)
            )
            #expect(weeks.count <= 1)
        }
    }

    @Test("Hostile text in the name, the tag and an exercise name is stored whole", arguments: [
        "", " ", "💪🏽 Bench — día 1", "Robert'); DROP TABLE workout;--", "e\u{301}\u{200B}\u{FEFF}", "%_\\[*?",
        String(repeating: "長", count: 10000), "\u{1}\u{7F}\u{2400}\\0", "line\nbreak\ttab"
    ])
    func hostileText_roundTrips(text: String) async throws {
        let stack = try await S3Kit.stack()
        var workout = S3Kit.mixed(1)
        workout.name = text
        workout.tag = text
        workout.exercises[1].name = text
        try await stack.materialize(workout)
        #expect(try await stack.workouts.workout(id: workout.id) == workout)
        try await stack.materialize(workout)
        #expect(try await stack.texts("SELECT DISTINCT updated_at FROM workout_exercise").count == 1)
    }

    @Test("U+0000 anywhere in a name or tag is refused by column; the stored workout keeps every byte", arguments: [
        "\0", "\0Bench", "Bench\0", "Be\0nch", "Be\u{301}\0", "\0\0"
    ])
    func nul_isRefusedByColumn(text: String) async throws {
        let stack = try await S3Kit.stack()
        let stored = S3Kit.mixed(1)
        try await stack.materialize(stored)
        stack.clock.advance()
        let before = try await stack.dump()
        for (column, keyPath) in [
            ("workout.name", \WorkoutState.name), ("workout.tag", \.tag), ("workout_exercise.name", \.exercises[1].name)
        ] {
            var workout = S3Kit.mixed(1)
            workout.exercises[0].sets[0].reps = Reps(clamping: 9) // a change in a row written before the refusal
            workout[keyPath: keyPath] = text
            await #expect(throws: LedgerPersistenceError.nulInText(column)) { try await stack.materialize(workout) }
            #expect(try await stack.dump() == before, "\(column)")
        }
    }
}
