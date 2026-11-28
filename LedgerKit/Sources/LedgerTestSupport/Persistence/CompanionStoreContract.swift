import Foundation
import LedgerDomain

/// `CompanionStore`'s contract as named clauses (F19 S3a): the finished logs' outbox order, stamps, compaction and
/// 14-day sweep, the state, and the last-performance cache, at the storage boundary. `GRDBCompanionStore` and
/// `InMemoryCompanionStore` each run every clause in `LedgerPersistenceTests`, on a fresh, empty store.
public enum CompanionStoreContract {
    public typealias Clause = ContractClause<any CompanionStore>

    public static let clauses: [Clause] = [
        Clause("a saved log lists back exactly; saving it again replaces only the record", savesAndReplaces),
        Clause("unacknowledged logs list oldest first, then by workout id; acknowledged ones never", ordersTheOutbox),
        Clause(
            "markEnqueued keeps the first stamp; acknowledging is for good; both ignore unknown workouts",
            stampsOnce
        ),
        Clause("compactAcknowledged deletes the acknowledged logs, and only them", compactsAcknowledged),
        Clause("pruneArchives deletes logs older than 14 days, acknowledged or not, and no other", prunes),
        Clause("a date that is not finite throws nonFiniteDate and stores nothing", refusesNonFiniteDates),
        Clause("the state is empty before a save, then exactly as saved, replaced whole", savesState),
        Clause("last performance is replaced whole, with exact weights and dates", replacesLastPerformance),
        Clause("an inexact last-performance weight throws inexactWeight and keeps what was stored", refusesInexact)
    ]

    /// 2026-09-16T05:20:00Z.
    public static let now = Date(timeIntervalSinceReferenceDate: 811_228_800.125)

    /// A workout's record as the watch sends it: a started envelope, a HealthKit UUID and a fractional finish.
    public static func record(_ number: Int) -> FinishedWorkoutRecord {
        let workout = WorkoutID(EventBuilders.uuid(0xC000 + number))
        return FinishedWorkoutRecord(
            workoutID: workout,
            log: EventBuilders.log(from: [.started(EventBuilders.seedSession())], workoutID: workout),
            healthKitUUID: EventBuilders.uuid(0xBEEF),
            finishedAt: now.addingTimeInterval(-0.000_123),
            device: EventBuilders.watch
        )
    }

    static func ids(_ store: any CompanionStore) async throws -> [WorkoutID] {
        try await store.unacknowledgedLogs().map(\.record.workoutID)
    }

    static func savesAndReplaces(_ store: any CompanionStore) async throws -> String? {
        let first = record(1)
        try await store.saveFinishedLog(first, createdAt: now)
        let saved = try await store.unacknowledgedLogs()
        try await store.markEnqueued([first.workoutID], at: now.addingTimeInterval(1))
        var second = first
        second.healthKitUUID = nil
        second.log = []
        try await store.saveFinishedLog(second, createdAt: now.addingTimeInterval(60))
        let replaced = try await store.unacknowledgedLogs()
        let expected = FinishedLogEntry(record: second, createdAt: now, enqueuedAt: now.addingTimeInterval(1))
        return ContractCheck.expect(
            saved,
            [FinishedLogEntry(record: first, createdAt: now, enqueuedAt: nil)],
            "the log"
        )
            ?? ContractCheck.expect(replaced, [expected], "the log saved again")
    }

    static func ordersTheOutbox(_ store: any CompanionStore) async throws -> String? {
        // Saved out of order; 3 and 2 share a created-at, so the workout id orders them.
        try await store.saveFinishedLog(record(3), createdAt: now)
        try await store.saveFinishedLog(record(4), createdAt: now.addingTimeInterval(-60))
        try await store.saveFinishedLog(record(2), createdAt: now)
        try await store.saveFinishedLog(record(1), createdAt: now.addingTimeInterval(0.001))
        try await store.saveFinishedLog(record(5), createdAt: now.addingTimeInterval(-120))
        try await store.markEnqueued([record(2).workoutID], at: now)
        try await store.acknowledge([record(5).workoutID], at: now)
        let expected = [4, 2, 3, 1].map { record($0).workoutID }
        return try await ContractCheck.expect(ids(store), expected, "the unacknowledged logs")
    }

    static func stampsOnce(_ store: any CompanionStore) async throws -> String? {
        let workout = record(1).workoutID
        try await store.saveFinishedLog(record(1), createdAt: now)
        try await store.markEnqueued([workout, record(9).workoutID], at: now.addingTimeInterval(1))
        try await store.markEnqueued([workout], at: now.addingTimeInterval(2))
        let enqueued = try await store.unacknowledgedLogs().map(\.enqueuedAt)
        try await store.acknowledge([workout, record(9).workoutID], at: now.addingTimeInterval(3))
        try await store.acknowledge([workout], at: now.addingTimeInterval(4))
        let afterAck = try await ids(store)
        // Saved again, the acknowledged log stays out of the list; the one acknowledged before it was stored is in it.
        try await store.saveFinishedLog(record(1), createdAt: now)
        try await store.saveFinishedLog(record(9), createdAt: now)
        return try await ContractCheck.first(
            ContractCheck.expect(enqueued, [now.addingTimeInterval(1)], "enqueuedAt after two marks"),
            ContractCheck.expect(afterAck, [], "the unacknowledged logs after the acknowledgement"),
            ContractCheck.expect(
                store.unacknowledgedLogs(),
                [FinishedLogEntry(record: record(9), createdAt: now, enqueuedAt: nil)],
                "the logs saved again: an unknown workout's marks were ignored"
            )
        )
    }

    static func compactsAcknowledged(_ store: any CompanionStore) async throws -> String? {
        for number in 1 ... 3 {
            try await store.saveFinishedLog(record(number), createdAt: now.addingTimeInterval(Double(number)))
        }
        try await store.acknowledge([record(1).workoutID, record(3).workoutID], at: now)
        try await store.compactAcknowledged()
        // Gone, so saving them again stores new, unacknowledged logs; the kept one keeps its created-at.
        for number in 1 ... 3 {
            try await store.saveFinishedLog(record(number), createdAt: now.addingTimeInterval(10))
        }
        let expected = [2, 1, 3].map { record($0).workoutID }
        return try await ContractCheck.expect(ids(store), expected, "the logs after compaction and a second save")
    }

    static func prunes(_ store: any CompanionStore) async throws -> String? {
        let retention = FinishedLogEntry.archiveRetention
        try await store.saveFinishedLog(record(1), createdAt: now.addingTimeInterval(-retention))
        try await store.saveFinishedLog(record(2), createdAt: now.addingTimeInterval(-retention - 0.001))
        try await store.saveFinishedLog(record(3), createdAt: now.addingTimeInterval(-retention - 86400))
        try await store.saveFinishedLog(record(4), createdAt: now)
        try await store.saveFinishedLog(record(5), createdAt: now.addingTimeInterval(-retention + 1))
        try await store.acknowledge([record(5).workoutID, record(3).workoutID], at: now)
        try await store.pruneArchives(now: now)
        let kept = try await ids(store)
        // Saved again, the young acknowledged log is still acknowledged (compaction, not the sweep, deletes it); the
        // old one was deleted, acknowledgement and all, so it comes back as a new log.
        try await store.saveFinishedLog(record(5), createdAt: now)
        try await store.saveFinishedLog(record(3), createdAt: now)
        return try await ContractCheck.first(
            ContractCheck.expect(kept, [1, 4].map { record($0).workoutID }, "the logs after the sweep"),
            ContractCheck.expect(ids(store), [1, 3, 4].map { record($0).workoutID }, "the logs saved again")
        )
    }

    static func refusesNonFiniteDates(_ store: any CompanionStore) async throws -> String? {
        let (workout, refused) = (record(1).workoutID, RepositoryError.nonFiniteDate)
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        try await store.saveFinishedLog(record(1), createdAt: now)
        return try await ContractCheck.first(
            ContractCheck.expectError(refused) { try await store.saveFinishedLog(record(2), createdAt: nan) },
            ContractCheck.expectError(refused) { try await store.markEnqueued([workout], at: nan) },
            ContractCheck.expectError(refused) { try await store.acknowledge([workout], at: nan) },
            ContractCheck.expectError(refused) { try await store.pruneArchives(now: nan) },
            ContractCheck.expect(
                store.unacknowledgedLogs(),
                [FinishedLogEntry(record: record(1), createdAt: now, enqueuedAt: nil)],
                "the logs after the refusals"
            )
        )
    }
}

/// The state and the last-performance cache.
extension CompanionStoreContract {
    static func savesState(_ store: any CompanionStore) async throws -> String? {
        let empty = try await store.state()
        let context = CompanionContext(
            revision: 1_789_536_000_123,
            programID: ProgramID(EventBuilders.uuid(0xA001)),
            programName: "Upper / Lower",
            weekIndex: 4,
            weekCount: 12,
            isDeload: true,
            nextDay: nil,
            settings: WatchSettings(.default),
            acknowledgedWorkoutIDs: [record(1).workoutID]
        )
        let full = CompanionState(context: context, programFileSHA256: Data(repeating: 0xAB, count: 32))
        try await store.saveState(full)
        let saved = try await store.state()
        let partial = CompanionState(context: nil, programFileSHA256: Data([0x01]))
        try await store.saveState(partial)
        return try await ContractCheck.first(
            ContractCheck.expect(empty, .empty, "the state before a save"),
            ContractCheck.expect(saved, full, "the saved state"),
            ContractCheck.expect(store.state(), partial, "the state saved again")
        )
    }

    static let squat = ExerciseID(EventBuilders.uuid(0x0CA0_0001))
    static let bench = ExerciseID(EventBuilders.uuid(0x0CA0_0002))

    static func replacesLastPerformance(_ store: any CompanionStore) async throws -> String? {
        let empty = try await store.lastPerformance()
        let lines = [
            squat: LastPerformance(date: now.addingTimeInterval(-0.5), sets: 5, reps: 5, load: .kilograms(102.5)),
            bench: LastPerformance(date: now, sets: 3, reps: 8, load: .pounds(182.5))
        ]
        try await store.replaceLastPerformance(lines)
        let saved = try await store.lastPerformance()
        let fewer = [bench: LastPerformance(date: now, sets: 4, reps: 6, load: .pounds(0.25))]
        try await store.replaceLastPerformance(fewer)
        return try await ContractCheck.first(
            ContractCheck.expect(empty, [:], "last performance before a save"),
            ContractCheck.expect(saved, lines, "the saved last performance"),
            ContractCheck.expect(store.lastPerformance(), fewer, "last performance replaced")
        )
    }

    /// ⅛ lb is half a stored unit, so the whole replacement is refused, the exact line with it.
    static func refusesInexact(_ store: any CompanionStore) async throws -> String? {
        let kept = [squat: LastPerformance(date: now, sets: 5, reps: 5, load: .kilograms(100))]
        try await store.replaceLastPerformance(kept)
        let eighth = Weight(grams: Decimal(string: "56.69904625") ?? 0)
        return try await ContractCheck.first(
            ContractCheck.expectError(RepositoryError.inexactWeight(eighth.grams)) {
                try await store.replaceLastPerformance([
                    bench: LastPerformance(date: now, sets: 1, reps: 1, load: .kilograms(20)),
                    squat: LastPerformance(date: now, sets: 1, reps: 1, load: eighth)
                ])
            },
            ContractCheck.expect(store.lastPerformance(), kept, "last performance kept")
        )
    }
}
