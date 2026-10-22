import Foundation
import LedgerDomain

/// The Library's batch read (F12 S1, N3): `bestSets()` is `bestSet(exerciseID:)` of every exercise, in one read.
extension StatsQueriesContract {
    /// Empty, then over a history that reaches every rule of the best set:
    /// - bench's best is 200 × 3, an added set, over a 200 × 2 and over a heavier set left undone, a heavier drop
    ///   set and a heavier warm-up;
    /// - the row's is 300 × 10, the more reps of two sets as heavy, in two workouts;
    /// - the squat's 315 × 5 is in a workout that is deleted, so the squat has no entry;
    /// - the fourth exercise has only warm-ups and no entry; the fifth and sixth were never logged.
    ///
    /// Every exercise's entry equals what `bestSet(exerciseID:)` says of it, and one with none has no key.
    static func bestSets(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let empty = try await stats.bestSets()
        try await stores.materialize(Seeders.workout(number: 0, endedAt: day(-7), [
            Seeders.ExerciseLog(bench, [.init(200, 2), .init(250, 1, .drop), .init(240, 2, .warmup)]),
            .straight(row, sets: 3, reps: 8, pounds: 300),
            Seeders.ExerciseLog(Workouts.exercises[3], [.init(95, 5, .warmup)])
        ]))
        try await stores.materialize(Seeders.workout(number: 1, endedAt: now, [
            Seeders.ExerciseLog(bench, [.init(180, 5), .init(200, 3, .added), .init(225, 1, done: false)]),
            Seeders.ExerciseLog(row, [.init(300, 10), .init(290, 12)])
        ]))
        let deleted = Seeders.workout(number: 2, endedAt: day(-3), [.straight(squat, sets: 3, reps: 5, pounds: 315)])
        try await stores.materialize(deleted)
        try await stores.workouts.delete(id: deleted.id)
        let all = try await stats.bestSets()
        var differences: [String] = []
        for exercise in Workouts.exercises {
            let one = try await stats.bestSet(exerciseID: exercise.id).map { BestSet(weight: $0.weight, reps: $0.reps) }
            if all[exercise.id] != one {
                let batch = String(describing: all[exercise.id])
                differences.append("\(exercise.name): bestSets \(batch), bestSet \(String(describing: one))")
            }
        }
        return ContractCheck.first(
            ContractCheck.expect(empty, [:], "bestSets of an empty history"),
            ContractCheck.expect(all[bench.id], BestSet(weight: .pounds(200), reps: Reps(clamping: 3)), "bench's best"),
            ContractCheck.expect(
                all[row.id],
                BestSet(weight: .pounds(300), reps: Reps(clamping: 10)),
                "the row's best"
            ),
            ContractCheck.expect(Set(all.keys), [bench.id, row.id], "the exercises with a best"),
            ContractCheck.expect(differences, [], "bestSets against bestSet(exerciseID:)")
        )
    }
}
