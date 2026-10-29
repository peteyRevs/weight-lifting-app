import Foundation
import LedgerDomain

/// A past workout's detail (F13 S2, N8): `observeWorkout(id:)`, on the GRDB repository and the in-memory one, over the
/// same `HistoryStores`. Each value is checked against `workout(id:)` and the records the stats list for that
/// workout, read then.
public extension WorkoutRepositoryContract {
    static let detailClauses: [Clause] = [
        Clause(
            "observeWorkout emits nil for a workout not stored, nothing for another's save, then the workout stored",
            observeWorkoutFromNothing
        ),
        Clause(
            "observeWorkout follows its edit, an earlier workout's edit that takes its record away, and its delete",
            observeWorkoutFollowsEdits
        ),
        Clause(
            "observeWorkout emits nothing for a save or delete of another workout that leaves its records",
            observeWorkoutIgnoresOthers
        )
    ]
}

extension WorkoutRepositoryContract {
    /// An older bench workout of 185, and a newer one of 190 a day later, which sets records over it.
    private static func olderAndNewer() -> (older: WorkoutState, newer: WorkoutState) {
        let bench = exercises[0]
        let older = Seeders.workout(number: 1, endedAt: EventBuilders.start, [
            .straight(bench, sets: 1, reps: 5, pounds: 185)
        ])
        let newer = Seeders.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(86400), [
            .straight(bench, sets: 2, reps: 5, pounds: 190)
        ])
        return (older, newer)
    }

    /// Before the workout is stored the stream says nil; an earlier workout's save leaves that as it is, and the
    /// workout's own save emits it with the records it set.
    static func observeWorkoutFromNothing(_ stores: HistoryStores) async throws -> String? {
        let (older, newer) = olderAndNewer()
        let values = StreamArrivals(stores.workouts.observeWorkout(id: newer.id))
        defer { values.cancel() }
        let first = await values.next()
        try await stores.materialize(older)
        let afterOther = await values.next(within: StatsQueriesContract.quiet)
        try await stores.materialize(newer)
        let stored = await values.next()
        let expected = try await expectedRecorded(newer.id, in: stores)
        return ContractCheck.first(
            ContractCheck.expect(first.map { $0 == nil }, true, "the first value is nil"),
            ContractCheck.expect(afterOther.map { _ in "a value" }, nil, "a value after another workout's save"),
            ContractCheck.expect(stored, .some(expected), "the value once stored"),
            ContractCheck.expect(expected?.records.isEmpty, false, "the records it set")
        )
    }

    /// N8: the newer workout's value after its own edit, after the older workout's bench is raised past it (which
    /// takes its records away) and after its delete, which emits nil.
    static func observeWorkoutFollowsEdits(_ stores: HistoryStores) async throws -> String? {
        let (older, newer) = olderAndNewer()
        try await stores.materialize(older)
        try await stores.materialize(newer)
        let values = StreamArrivals(stores.workouts.observeWorkout(id: newer.id))
        defer { values.cancel() }
        var issues = try await [
            ContractCheck.expect(values.next(), .some(expectedRecorded(newer.id, in: stores)), "the first value")
        ]
        var fewer = newer.exercises[0].sets
        fewer.removeLast()
        var raised = older.exercises[0].sets
        raised[0].weight = .pounds(225)
        let steps: [(String, () async throws -> Void)] = [
            ("its own edit", {
                try await stores.workouts.updateSets(workoutExerciseID: newer.exercises[0].id, sets: fewer)
            }),
            ("an earlier workout's edit", {
                try await stores.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: raised)
            }),
            ("its delete", { try await stores.workouts.delete(id: newer.id) })
        ]
        for (what, step) in steps {
            try await step()
            let value = await values.next()
            try await issues.append(ContractCheck.expect(value, .some(expectedRecorded(newer.id, in: stores)), what))
        }
        let read = try await stores.workouts.workout(id: newer.id)
        issues.append(ContractCheck.expect(read == nil, true, "the workout is gone"))
        return issues.lazy.compactMap(\.self).first
    }

    /// N8's "and for no other write": a later workout of another exercise saved and deleted, and a log appended
    /// (when the stores hold one), leave the workout and its records as they were, and emit nothing. Its own delete
    /// still emits nil, so the stream is alive.
    static func observeWorkoutIgnoresOthers(_ stores: HistoryStores) async throws -> String? {
        let (older, _) = olderAndNewer()
        let other = Seeders.workout(number: 3, endedAt: EventBuilders.start.addingTimeInterval(86400), [
            .straight(exercises[1], sets: 1, reps: 5, pounds: 225)
        ])
        try await stores.materialize(older)
        let values = StreamArrivals(stores.workouts.observeWorkout(id: older.id))
        defer { values.cancel() }
        let first = await values.next()
        var issues = [ContractCheck.expect(first.map { $0 != nil }, true, "the first value")]
        let writes: [(String, () async throws -> Void)] = [
            ("another workout's save", { try await stores.materialize(other) }),
            ("another workout's delete", { try await stores.workouts.delete(id: other.id) }),
            ("a log append", { _ = try await stores.events?.append(log(of: Seeders.workoutID(9), count: 3)) })
        ]
        for (what, write) in writes {
            try await write()
            let value = await values.next(within: StatsQueriesContract.quiet)
            issues.append(ContractCheck.expect(value.map { _ in "a value" }, nil, "a value after \(what)"))
        }
        try await stores.workouts.delete(id: older.id)
        let afterDelete = await values.next()
        issues.append(ContractCheck.expect(afterDelete.map { $0 == nil }, true, "nil after its delete"))
        return issues.lazy.compactMap(\.self).first
    }

    /// The workout `id` as `workout(id:)` reads it, with the records the stats list for it, by exercise id text, then
    /// the estimated 1RM first; nil when it is not stored.
    private static func expectedRecorded(_ id: WorkoutID, in stores: HistoryStores) async throws -> RecordedWorkout? {
        guard let stored = try await stores.workouts.workout(id: id) else {
            return nil
        }
        var records: [PersonalRecord] = []
        for exerciseID in Set(stored.exercises.map(\.exerciseID)) {
            records += try await stores.stats.personalRecords(exerciseID: exerciseID).filter { $0.workoutID == id }
        }
        let sorted = records.sorted { lhs, rhs in
            let left = (lhs.exerciseID.rawValue.uuidString, isWeight(lhs.kind))
            let right = (rhs.exerciseID.rawValue.uuidString, isWeight(rhs.kind))
            return left.0 != right.0 ? left.0 < right.0 : !left.1 && right.1
        }
        return RecordedWorkout(workout: stored, records: sorted)
    }

    private static func isWeight(_ kind: PRKind) -> Bool {
        if case .weightAtReps = kind {
            return true
        }
        return false
    }
}
