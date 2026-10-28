import Foundation
import LedgerDomain

/// The History list's clauses (F13 S1, N1 and N2): `historyEntries()` and its observation, on the GRDB repository
/// and the in-memory one, over the same `HistoryStores`.
public extension WorkoutRepositoryContract {
    static let historyClauses: [Clause] = [
        Clause(
            "historyEntries lists every stored workout newest first, each what workout(id:) and its records say",
            historyEntries
        ),
        Clause(
            "historyEntries follows an edit: its volume and records, and a later workout's record it takes away",
            historyEntriesFollowEdits
        ),
        Clause(
            "observeHistoryEntries follows a finish, an edit and a delete, the oldest too, and no log append",
            observeHistoryEntries
        )
    ]
}

extension WorkoutRepositoryContract {
    private static var bench: Exercise {
        exercises[0]
    }

    /// N1: three workouts, two started together (the smaller id first), the second of them with a record over the
    /// first workout's bench (a first set is a baseline, no record); a deleted fourth is left out. Each entry equals
    /// the one computed from `workout(id:)`, with as many records as the stats list for that workout.
    static func historyEntries(_ stores: HistoryStores) async throws -> String? {
        let start = EventBuilders.start
        let first = Seeders.workout(number: 1, endedAt: start, [.straight(bench, sets: 3, reps: 5, pounds: 185)])
        let later = workout(number: 2, endedAt: start.addingTimeInterval(3600))
        // Started with `later`, and its id sorts after it.
        let tied = Seeders.workout(number: 3, endedAt: start.addingTimeInterval(3600), [
            .straight(bench, sets: 1, reps: 5, pounds: 205)
        ])
        let deleted = Seeders.workout(number: 4, endedAt: start.addingTimeInterval(7200), [
            .straight(bench, sets: 1, reps: 1, pounds: 300)
        ])
        for workout in [first, later, tied, deleted] {
            try await stores.materialize(workout)
        }
        try await stores.workouts.delete(id: deleted.id)
        let entries = try await stores.workouts.historyEntries()
        let expected = try await expectedEntries([later, tied, first], in: stores)
        return ContractCheck.first(
            ContractCheck.expect(entries.map(\.id), [later.id, tied.id, first.id], "the order"),
            ContractCheck.expect(entries, expected, "the entries"),
            ContractCheck.expect(entries.first { $0.id == tied.id }.map { $0.prCount > 0 }, true, "the record")
        )
    }

    /// N1: an older workout's set raised past a later one's takes the later one's record away; its volume and its
    /// own records follow, read back as `workout(id:)` and the stats say.
    static func historyEntriesFollowEdits(_ stores: HistoryStores) async throws -> String? {
        let older = Seeders.workout(number: 1, endedAt: EventBuilders.start, [
            .straight(bench, sets: 1, reps: 5, pounds: 185)
        ])
        let newer = Seeders.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(86400), [
            .straight(bench, sets: 1, reps: 5, pounds: 190)
        ])
        try await stores.materialize(older)
        try await stores.materialize(newer)
        let before = try await stores.workouts.historyEntries()
        var raised = older.exercises[0].sets
        raised[0].weight = .pounds(225)
        try await stores.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: raised)
        let after = try await stores.workouts.historyEntries()
        var edited = older
        edited.exercises[0].sets = raised
        return try await ContractCheck.first(
            ContractCheck.expect(before.first.map { $0.prCount > 0 }, true, "the newer workout's record before"),
            ContractCheck.expect(after.first?.prCount, 0, "the newer workout's records after"),
            ContractCheck.expect(after.last?.volume, edited.volume, "the edited workout's volume"),
            ContractCheck.expect(after, expectedEntries([newer, edited], in: stores), "the entries after the edit")
        )
    }

    /// N2: what `observeHistoryEntries()` emits now and after each write, against `historyEntries()` read then.
    /// Appending to a workout's log, a live workout's set taps, emits nothing (when the stores hold a log).
    static func observeHistoryEntries(_ stores: HistoryStores) async throws -> String? {
        let oldest = Seeders.workout(number: 1, endedAt: EventBuilders.start, [
            .straight(bench, sets: 2, reps: 5, pounds: 185)
        ])
        let newest = Seeders.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(86400), [
            .straight(bench, sets: 1, reps: 5, pounds: 175)
        ])
        let values = StreamArrivals(stores.workouts.observeHistoryEntries())
        defer { values.cancel() }
        let first = await values.next()
        var issues = [ContractCheck.expect(first, [], "the first value")]
        let steps: [(String, () async throws -> Void)] = [
            ("a finish", { try await stores.materialize(oldest) }),
            ("a newer finish", { try await stores.materialize(newest) }),
            ("an edit of the oldest", {
                try await stores.workouts.updateSets(
                    workoutExerciseID: oldest.exercises[0].id,
                    sets: Array(oldest.exercises[0].sets.prefix(1))
                )
            }),
            ("a delete of the oldest", { try await stores.workouts.delete(id: oldest.id) })
        ]
        for (what, step) in steps {
            try await step()
            let value = await values.next()
            let read = try await stores.workouts.historyEntries()
            issues.append(ContractCheck.expect(value, read, "the value after \(what)"))
        }
        if let events = stores.events {
            _ = try await events.append(log(of: Seeders.workoutID(9), count: 3))
            let value = await values.next(within: StatsQueriesContract.quiet)
            issues.append(ContractCheck.expect(value.map { _ in "a value" }, nil, "a value after a log append"))
        }
        return issues.lazy.compactMap(\.self).first
    }

    /// Each of `workouts`' entries as `workout(id:)` reads it, counting the records the stats list for it.
    private static func expectedEntries(
        _ workouts: [WorkoutState],
        in stores: HistoryStores
    ) async throws -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        for workout in workouts {
            guard let stored = try await stores.workouts.workout(id: workout.id) else {
                continue
            }
            var records = 0
            for exerciseID in Set(stored.exercises.map(\.exerciseID)) {
                records += try await stores.stats.personalRecords(exerciseID: exerciseID)
                    .count { $0.workoutID == workout.id }
            }
            entries.append(HistoryEntry(stored, prCount: records))
        }
        return entries
    }
}
