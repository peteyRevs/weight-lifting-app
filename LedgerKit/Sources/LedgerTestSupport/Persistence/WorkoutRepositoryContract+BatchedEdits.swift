import Foundation
import LedgerDomain

/// One write for a multi-exercise edit (F13 S3, ruling A4): `updateSets(_:of:)`, on the GRDB repository and the
/// in-memory one, over the same `HistoryStores`.
public extension WorkoutRepositoryContract {
    static let batchedEditClauses: [Clause] = [
        Clause("A batched updateSets stores every exercise named, and detects the records of each", batchedStoresAll),
        Clause("A bad id, or a workout that is not stored, stores nothing and throws missingRow", batchedAllOrNothing),
        Clause("A batched updateSets is one change to the list's and the detail's observers", batchedEmitsOnce),
        Clause(
            "A one-entry batch equals updateSets(workoutExerciseID:sets:); an empty one stores nothing",
            batchedOfOne
        )
    ]
}

extension WorkoutRepositoryContract {
    /// An older workout of two exercises, then a newer one that sets records over each.
    private static func twoLifts() -> (older: WorkoutState, newer: WorkoutState) {
        let older = Seeders.workout(number: 1, endedAt: EventBuilders.start, [
            .straight(exercises[0], sets: 2, reps: 5, pounds: 185),
            .straight(exercises[1], sets: 2, reps: 5, pounds: 225)
        ])
        let newer = Seeders.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(86400), [
            .straight(exercises[0], sets: 2, reps: 5, pounds: 190),
            .straight(exercises[1], sets: 2, reps: 5, pounds: 230)
        ])
        return (older, newer)
    }

    private static func lifted(_ sets: [LoggedSet], pounds: Decimal) -> [LoggedSet] {
        sets.map { set in
            var lifted = set
            lifted.weight = .pounds(pounds)
            return lifted
        }
    }

    /// Both of the older workout's exercises raised past the newer workout's in one call: the sets are stored, and
    /// the newer workout loses its records on both exercises, which only a replay over both can do.
    static func batchedStoresAll(_ stores: HistoryStores) async throws -> String? {
        let (older, newer) = twoLifts()
        try await stores.materialize(older)
        try await stores.materialize(newer)
        var edited = older
        edited.exercises[0].sets = lifted(older.exercises[0].sets, pounds: 300)
        edited.exercises[1].sets = lifted(older.exercises[1].sets, pounds: 400)
        try await stores.workouts.updateSets(
            [edited.exercises[0].id: edited.exercises[0].sets, edited.exercises[1].id: edited.exercises[1].sets],
            of: older.id
        )
        let read = try await stores.workouts.workout(id: older.id)
        let records = try await [
            stores.stats.personalRecords(exerciseID: exercises[0].id),
            stores.stats.personalRecords(exerciseID: exercises[1].id)
        ]
        let held = records.flatMap(\.self).filter { $0.workoutID == newer.id }
        let entries = try await stores.workouts.historyEntries()
        return ContractCheck.first(
            ContractCheck.expect(read?.exercises[0].sets, edited.exercises[0].sets, "the first exercise's sets"),
            ContractCheck.expect(read?.exercises[1].sets, edited.exercises[1].sets, "the second exercise's sets"),
            ContractCheck.expect(held.count, 0, "the newer workout's records on both exercises"),
            ContractCheck.expect(entries.first { $0.id == newer.id }?.prCount, 0, "the newer workout's count")
        )
    }

    /// An id of another workout beside a good one, an unknown workout and a deleted one: each throws `missingRow`, and
    /// nothing moved. The map's order is the hash's, so the bad id may come first or last.
    static func batchedAllOrNothing(_ stores: HistoryStores) async throws -> String? {
        let (older, newer) = twoLifts()
        try await stores.materialize(older)
        try await stores.materialize(newer)
        let good = lifted(older.exercises[0].sets, pounds: 300)
        let isMissing = { (error: any Error) -> Bool in
            if case RepositoryError.missingRow = error {
                return true
            }
            return false
        }
        var issues: [String?] = []
        for (what, map, workout) in [
            (
                "another workout's exercise",
                [older.exercises[0].id: good, newer.exercises[0].id: newer.exercises[0].sets],
                older.id
            ),
            ("an unknown exercise", [older.exercises[0].id: good, WorkoutExerciseID(UUID()): []], older.id),
            ("an unknown workout", [older.exercises[0].id: good], Seeders.workoutID(99))
        ] {
            do {
                try await stores.workouts.updateSets(map, of: workout)
                issues.append("\(what): no error")
            } catch {
                issues.append(ContractCheck.expect(isMissing(error), true, "\(what): \(error)"))
            }
            let read = try await stores.workouts.workout(id: older.id)
            issues.append(ContractCheck.expect(read?.exercises[0].sets, older.exercises[0].sets, "after \(what)"))
        }
        try await stores.workouts.delete(id: newer.id)
        do {
            try await stores.workouts.updateSets([newer.exercises[0].id: []], of: newer.id)
            issues.append("a deleted workout: no error")
        } catch {
            issues.append(ContractCheck.expect(isMissing(error), true, "a deleted workout: \(error)"))
        }
        return issues.lazy.compactMap(\.self).first
    }

    /// N2 and N8: a call over two exercises reaches each observer once, however many exercises it names.
    static func batchedEmitsOnce(_ stores: HistoryStores) async throws -> String? {
        let (older, _) = twoLifts()
        try await stores.materialize(older)
        let list = StreamArrivals(stores.workouts.observeHistoryEntries())
        let detail = StreamArrivals(stores.workouts.observeWorkout(id: older.id))
        defer {
            list.cancel()
            detail.cancel()
        }
        _ = await list.next()
        _ = await detail.next()
        try await stores.workouts.updateSets(
            [
                older.exercises[0].id: lifted(older.exercises[0].sets, pounds: 300),
                older.exercises[1].id: lifted(older.exercises[1].sets, pounds: 400)
            ],
            of: older.id
        )
        let firstEntries = await list.next()
        let firstDetail = await detail.next()
        let moreEntries = await list.next(within: StatsQueriesContract.quiet)
        let moreDetail = await detail.next(within: StatsQueriesContract.quiet)
        return ContractCheck.first(
            ContractCheck.expect(firstEntries.map { _ in true }, true, "the list hears the edit"),
            ContractCheck.expect(firstDetail.map { _ in true }, true, "the detail hears the edit"),
            ContractCheck.expect(moreEntries.map { _ in "a value" }, nil, "a second value on the list"),
            ContractCheck.expect(moreDetail.map { _ in "a value" }, nil, "a second value on the detail")
        )
    }

    /// The old call and a batch of one give the same workout and records; an empty batch of a stored workout is
    /// silent.
    static func batchedOfOne(_ stores: HistoryStores) async throws -> String? {
        let (older, newer) = twoLifts()
        try await stores.materialize(older)
        try await stores.materialize(newer)
        let raised = lifted(older.exercises[0].sets, pounds: 300)
        try await stores.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: raised)
        let byTheOldCall = try await stores.workouts.workout(id: older.id)
        let recordsThen = try await stores.stats.personalRecords(exerciseID: exercises[0].id)
        try await stores.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: older.exercises[0].sets)
        try await stores.workouts.updateSets([older.exercises[0].id: raised], of: older.id)
        let byABatch = try await stores.workouts.workout(id: older.id)
        let recordsNow = try await stores.stats.personalRecords(exerciseID: exercises[0].id)
        let list = StreamArrivals(stores.workouts.observeHistoryEntries())
        defer { list.cancel() }
        _ = await list.next()
        try await stores.workouts.updateSets([:], of: older.id)
        let afterEmpty = await list.next(within: StatsQueriesContract.quiet)
        return ContractCheck.first(
            ContractCheck.expect(byABatch, byTheOldCall, "the workout"),
            ContractCheck.expect(recordsNow, recordsThen, "the records"),
            ContractCheck.expect(afterEmpty.map { _ in "a value" }, nil, "a value after an empty batch")
        )
    }
}
