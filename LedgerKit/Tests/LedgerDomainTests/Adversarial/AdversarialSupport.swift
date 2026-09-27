import Foundation
@testable import LedgerDomain
import Testing

// Helpers for the adversarial suites (F02 test pass). Expected values are derived from the
// brief and spec in each test, never from the implementation.

/// Grams in one pound, exactly (decision #9).
let gramsPerPound = dec("453.59237")

/// `text` pounds as a `Weight` (exact decimal, no float literal).
func pounds(_ text: String) -> Weight {
    .pounds(dec(text))
}

/// `text` kilograms as a `Weight`.
func kilos(_ text: String) -> Weight {
    .kilograms(dec(text))
}

/// `value` rounded to `scale` fractional digits under `mode`.
func decimalRounded(_ value: Decimal, scale: Int = 0, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
    var input = value
    var output = Decimal()
    NSDecimalRound(&output, &input, scale, mode)
    return output
}

/// `value` as an `Int` after rounding half away from zero (the spec's `Math.round` for positives).
func wholeNumber(_ value: Decimal) -> Int {
    NSDecimalNumber(decimal: decimalRounded(value)).intValue
}

/// A random multiple of `quantum` in `range` (inclusive, in units of `quantum`).
func randomMultiple(
    of quantum: Decimal,
    in range: ClosedRange<Int>,
    using generator: inout SeededGenerator
) -> Decimal {
    Decimal(Int.random(in: range, using: &generator)) * quantum
}

enum Adversarial {
    static let start = Fixtures.date(2026, 8, 17)
    /// `start` as the civil date a `Program` starts on (ADR-007).
    static let startDay = CivilDate(start, in: Fixtures.calendar)

    /// A done/undone set row with an explicit kind.
    static func row(
        _ number: Int,
        weight: Weight,
        reps: Int,
        kind: SetKind = .working,
        done: Bool = true
    ) -> LoggedSet {
        LoggedSet(
            id: SetID(Fixtures.uuid(30000 + number)),
            weight: weight,
            reps: Reps(clamping: reps),
            kind: kind,
            doneAt: done ? Fixtures.now : nil
        )
    }

    /// A workout exercise built directly from rows (no slot rules involved).
    static func exercise(
        _ exercise: Exercise = Fixtures.bench,
        index: Int = 0,
        rows: [LoggedSet],
        targetSets: Int? = nil,
        targetReps: Int = 5,
        rest: Int = 90,
        superset: Bool = false
    ) throws -> WorkoutExercise {
        try Fixtures.workoutExercise(
            exercise,
            index: index,
            sets: rows,
            targetSets: targetSets,
            targetReps: targetReps,
            rest: rest,
            superset: superset
        )
    }

    /// `count` working rows of `weight × reps` followed by `drops` drop rows.
    static func rows(_ count: Int, drops: Int = 0, base: Int = 0) -> [LoggedSet] {
        let working = (0 ..< count).map { row(base + $0, weight: pounds("100"), reps: 5) }
        let dropRows = (0 ..< drops).map { row(base + 500 + $0, weight: pounds("85"), reps: 5, kind: .drop) }
        return working + dropRows
    }

    /// A lb/kg exercise with explicit default start loads.
    static func catalogExercise(
        _ number: Int,
        _ equipment: Equipment,
        loads: [Units: Weight]
    ) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(number)),
            name: "Exercise \(number)",
            shortName: "EX\(number)",
            equipment: equipment,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: loads
        )
    }

    /// JSON round-trip through `[String: Any]` so a test can tamper with one field.
    static func tampered(_ value: some Codable, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The JSON fragment `value` encodes to (for splicing into a tampered object).
    static func fragment(_ value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }

    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}

extension PropertySeed {
    /// `all` plus seeds that once failed at the nightly count, kept as fixed regression cases
    /// (testing-strategy §3 rule 5) so the PR lane's 200 seeds always run them.
    static func all(plus regressions: [UInt64]) -> [PropertySeed] {
        let seeded = Set(all.map(\.value))
        return all + regressions.filter { !seeded.contains($0) }.map { PropertySeed(value: $0) }
    }
}
