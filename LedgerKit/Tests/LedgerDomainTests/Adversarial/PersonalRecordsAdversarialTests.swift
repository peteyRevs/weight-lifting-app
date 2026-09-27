import Foundation
@testable import LedgerDomain
import Testing

@Suite("PersonalRecords (adversarial)", .tags(.domain))
struct PersonalRecordsAdversarialTests {
    static func workout(_ exercises: [WorkoutExercise], deload: Bool = false) -> WorkoutState {
        Fixtures.workout(exercises, isDeload: deload)
    }

    static func benchWorkout(_ rows: [LoggedSet], deload: Bool = false) throws -> WorkoutState {
        try workout([Adversarial.exercise(rows: rows)], deload: deload)
    }

    static func detect(
        _ workout: WorkoutState,
        e1RM: Weight? = pounds("219"),
        atReps: [Int: String] = [5: "195"]
    ) throws -> [PersonalRecord] {
        let history = try Dictionary(uniqueKeysWithValues: atReps.map { try (Fixtures.reps($0.key), pounds($0.value)) })
        return PersonalRecords.detect(
            workout: workout,
            bestE1RM: e1RM.map { [Fixtures.bench.id: $0] } ?? [:],
            bestWeightAtReps: [Fixtures.bench.id: history],
            now: Fixtures.now
        )
    }

    static func e1RM(_ weight: String, _ reps: Int) throws -> Weight {
        try #require(OneRepMax.brzycki(weight: pounds(weight), reps: Fixtures.reps(reps)))
    }
}

extension PersonalRecordsAdversarialTests {
    @Test("200 × 5 against best e1RM 219 and best 195 × 5 fires both PR kinds (criterion 12).")
    func detect_criterion12_bothKinds() throws {
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds("200"), reps: 5)])
        let records = try Self.detect(workout)
        let expected: Set<PersonalRecord> = try [
            PersonalRecord(
                exerciseID: Fixtures.bench.id,
                kind: .estimatedOneRepMax(Self.e1RM("200", 5)),
                previous: .estimatedOneRepMax(pounds("219")),
                achievedAt: Fixtures.now,
                workoutID: Fixtures.workoutID
            ),
            PersonalRecord(
                exerciseID: Fixtures.bench.id,
                kind: .weightAtReps(pounds("200"), Fixtures.reps(5)),
                previous: .weightAtReps(pounds("195"), Fixtures.reps(5)),
                achievedAt: Fixtures.now,
                workoutID: Fixtures.workoutID
            )
        ]
        #expect(Set(records) == expected)
        #expect(records.count == 2)
        // ADR-007: 200 × 36 / 32 lb = 102,058.28325 g exactly; the estimate rounds to the nearest gram.
        #expect(try Self.e1RM("200", 5) == Weight(grams: 102_058))
        #expect(try Self.e1RM("200", 5).wholeValue(in: .lb) == 225)
    }

    @Test("Equalling the best e1RM or the best weight at the same reps is not a PR (decision #3).")
    func detect_ties_areNotPRs() throws {
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds("200"), reps: 5)])
        #expect(try Self.detect(workout, e1RM: Self.e1RM("200", 5), atReps: [5: "200"]).isEmpty)
    }

    @Test("A deload workout never produces PRs, however heavy (decision #3).")
    func detect_deload_neverPRs() throws {
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds("400"), reps: 5)], deload: true)
        #expect(try Self.detect(workout).isEmpty)
    }

    @Test("Undone, drop-only and warm-up-only sets never produce PRs.")
    func detect_ignoresUndoneDropAndWarmup() throws {
        let undone = try Self.benchWorkout([Adversarial.row(1, weight: pounds("400"), reps: 5, done: false)])
        let drop = try Self.benchWorkout([Adversarial.row(1, weight: pounds("400"), reps: 5, kind: .drop)])
        let warmup = try Self.benchWorkout([Adversarial.row(1, weight: pounds("400"), reps: 5, kind: .warmup)])
        for workout in [undone, drop, warmup] {
            #expect(try Self.detect(workout).isEmpty)
        }
    }

    @Test("A done added set counts like a working set.")
    func detect_addedSet_counts() throws {
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds("205"), reps: 5, kind: .added)])
        #expect(try Self.detect(workout).count == 2)
    }

    @Test("Above 12 reps there is no e1RM PR, but a weight PR at ≥ those reps still fires (decision #4).")
    func detect_highReps_weightPROnly() throws {
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds("150"), reps: 15)])
        let records = try Self.detect(workout, e1RM: pounds("1"), atReps: [15: "140"])
        #expect(try records.map(\.kind) == [.weightAtReps(pounds("150"), Fixtures.reps(15))])
    }

    @Test(
        "A weight PR must beat the best weight at the same or more reps (decision #3).",
        arguments: [
            ("200", 5, true), ("200", 3, false), ("185", 8, true), ("179", 8, false), ("210", 3, false), (
                "211",
                2,
                true
            )
        ]
    )
    func detect_weightAtReps_comparesAtOrAboveReps(weight: String, reps: Int, isPR: Bool) throws {
        // History: 210 × 3, 195 × 5, 180 × 8 → best at ≥ 5 is 195, at ≥ 3 is 210, at ≥ 8 is 180, at ≥ 2 is 210.
        let workout = try Self.benchWorkout([Adversarial.row(1, weight: pounds(weight), reps: reps)])
        let records = try Self.detect(workout, e1RM: pounds("1000"), atReps: [3: "210", 5: "195", 8: "180"])
        #expect(records.contains {
            if case .weightAtReps = $0.kind {
                true
            } else {
                false
            }
        } == isPR)
    }

    @Test("The e1RM PR reports the best estimate across the exercise's sets.")
    func detect_e1RM_bestAcrossSets() throws {
        // 205 × 5 → 230.6 lb beats 210 × 3 → 222.4 lb.
        let workout = try Self.benchWorkout([
            Adversarial.row(1, weight: pounds("210"), reps: 3), Adversarial.row(2, weight: pounds("205"), reps: 5)
        ])
        let records = try Self.detect(workout, atReps: [1: "500"])
        #expect(try records.map(\.kind) == [.estimatedOneRepMax(Self.e1RM("205", 5))])
    }

    @Test("An exercise performed twice in one workout yields at most one PR of each kind.")
    func detect_sameExerciseTwice_oneRecordPerKind() throws {
        let first = try Adversarial.exercise(index: 0, rows: [Adversarial.row(1, weight: pounds("200"), reps: 5)])
        let second = try Adversarial.exercise(index: 1, rows: [Adversarial.row(2, weight: pounds("205"), reps: 5)])
        let records = try Self.detect(Self.workout([first, second]))
        #expect(records.count == 2)
        #expect(try records.contains { try $0.kind == .estimatedOneRepMax(Self.e1RM("205", 5)) })
    }

    @Test("PRs are keyed to their own exercise; an exercise that beats nothing yields nothing.")
    func detect_multipleExercises_onlyBeatenOnes() throws {
        let bench = try Adversarial.exercise(index: 0, rows: [Adversarial.row(1, weight: pounds("200"), reps: 5)])
        let squat = try Adversarial.exercise(
            Fixtures.backSquat, index: 1, rows: [Adversarial.row(2, weight: pounds("100"), reps: 5)]
        )
        let records = try PersonalRecords.detect(
            workout: Self.workout([bench, squat]),
            bestE1RM: [Fixtures.bench.id: pounds("219"), Fixtures.backSquat.id: pounds("400")],
            bestWeightAtReps: [
                Fixtures.bench.id: [Fixtures.reps(5): pounds("195")],
                Fixtures.backSquat.id: [Fixtures.reps(5): pounds("350")]
            ],
            now: Fixtures.now
        )
        #expect(records.allSatisfy { $0.exerciseID == Fixtures.bench.id })
        #expect(records.count == 2)
    }
}
