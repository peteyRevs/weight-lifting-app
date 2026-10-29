import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S1 adversarial (G2): the History list's query and its observation, where the contract clauses are silent.
/// Random materialisations, edits and deletes (F05's `HistoryScript`, with tied starts, week edges and repeated ids)
/// run on GRDB and in memory; after every step both lists agree, every GRDB entry is what `workout(id:)` and the
/// receipt's own record rule say of it (N1, and the badge against the receipt), the list holds what `recent` holds,
/// and the observation has emitted exactly the changed lists, once each (N2).
@Suite(
    "Adversarial F13 S1 · the History list on GRDB and in memory",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct HistoryListAdversarialTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(40))

    static func describe(_ entries: [HistoryEntry]) -> String {
        entries.map { "\($0.name) \($0.volume) \($0.doneSets)/\($0.totalSets) PR\($0.prCount)" }
            .joined(separator: "; ")
    }

    /// The entry the receipt would agree with: the stored workout's own totals, and the records
    /// `PersonalRecords.detect` finds in it against the bests before it, which is how `WorkoutStore.records(of:)`
    /// counts the receipt's "N new PRs this session".
    static func receiptEntry(
        of id: WorkoutID,
        _ workouts: any WorkoutRepository,
        _ stats: any StatsQueries
    ) async throws -> HistoryEntry? {
        guard let workout = try await workouts.workout(id: id) else {
            return nil
        }
        let bests = try await stats.bests(before: workout, for: Set(workout.exercises.map(\.exerciseID)))
        let records = PersonalRecords.detect(workout: workout, against: bests, now: workout.startedAt)
        return HistoryEntry(workout, prCount: records.count)
    }

    /// The first disagreement of `seed`'s script, and the most workouts its list held (so a run can prove it listed).
    static func firstMismatch(
        _ seed: PropertySeed,
        waitsForQuiet: Bool
    ) async throws -> (mismatch: String?, mostListed: Int) {
        var mostListed = 0
        let mismatch = try await firstMismatch(seed, waitsForQuiet: waitsForQuiet, mostListed: &mostListed)
        return (mismatch, mostListed)
    }

    /// How GRDB's list `stored` disagrees with the fake's, with `recent(limit:)`, or with the receipt's rule.
    static func readMismatch(
        _ stored: [HistoryEntry],
        stack: S3Kit.Stack,
        stats: any StatsQueries,
        fakes: InMemoryStores
    ) async throws -> String? {
        let faked = try await fakes.workouts.historyEntries()
        guard stored == faked else {
            return "GRDB [\(describe(stored))], fake [\(describe(faked))]"
        }
        let recent = try await stack.workouts.recent(limit: 1000).map(\.id)
        guard recent == stored.map(\.id) else {
            return "the list and recent(limit:) hold different workouts"
        }
        for entry in stored {
            let wanted = try await receiptEntry(of: entry.id, stack.workouts, stats)
            guard wanted == entry else {
                return "\(describe([entry])) where the receipt's rule says " +
                    (wanted.map { describe([$0]) } ?? "nothing")
            }
        }
        return nil
    }

    static func firstMismatch(
        _ seed: PropertySeed,
        waitsForQuiet: Bool,
        mostListed: inout Int
    ) async throws -> String? {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let stats = stack.stats(now: script.now)
        let now = script.now
        let fakes = InMemoryStores(now: { now })
        let observed = LibraryArrivals(stack.workouts.observeHistoryEntries())
        defer { observed.cancel() }
        var shown = await observed.next(within: .seconds(5))
        guard shown == [] else {
            return "the first value is not the empty list"
        }
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            _ = await History.apply(operation, to: stack.workouts)
            _ = await History.apply(operation, to: fakes.workouts)
            let stored = try await stack.workouts.historyEntries()
            mostListed = max(mostListed, stored.count)
            if let mismatch = try await readMismatch(stored, stack: stack, stats: stats, fakes: fakes) {
                return "step \(step), \(operation): \(mismatch)"
            }
            if stored != shown {
                let value = await observed.next(within: .seconds(5))
                guard value == stored else {
                    return "step \(step), \(operation): observed [\(describe(value ?? []))], read [\(describe(stored))]"
                }
                shown = stored
            }
        }
        if waitsForQuiet, await observed.next(within: .milliseconds(200)) != nil {
            return "a value the reads did not change"
        }
        return nil
    }

    @Test("Random finishes, edits and deletes: GRDB's list is the fake's, the receipt's, recent's, and observed once")
    func historyList_agreesEverywhere() async throws {
        var proving = 0
        for (index, seed) in Self.seeds.enumerated() {
            // The quiet wait (no value the reads did not change) costs 200 ms, so a quarter of the seeds pay it.
            let (mismatch, mostListed) = try await Self.firstMismatch(seed, waitsForQuiet: index % 4 == 0)
            #expect(mismatch == nil, "\(seed)")
            proving += mostListed >= 2 ? 1 : 0
        }
        // Most scripts must list two workouts or more, or the agreement proves little.
        #expect(proving >= Self.seeds.count * 3 / 4, "only \(proving) of \(Self.seeds.count) scripts listed two")
    }

    // MARK: - A5: damaged rows

    /// Two stored workouts, the second damaged by an SQL statement, and the stack they are stored in.
    struct Damaged {
        let stack: S3Kit.Stack
        let first: WorkoutState
        let second: WorkoutState
    }

    /// Two workouts, the second with damaged sets or a damaged row, and the stack they are stored in.
    static func damaged(_ damage: String) async throws -> Damaged {
        let stack = try await S3Kit.stack()
        let first = S3Kit.workout(1, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        let second = S3Kit.workout(2, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(105, 5)])])
        try await stack.workouts.materialize(first, slotUpdates: [])
        try await stack.workouts.materialize(second, slotUpdates: [])
        let id = ColumnCodec.text(second.id)
        try await stack.queue.write { database in
            try database.execute(sql: damage, arguments: [id])
        }
        return Damaged(stack: stack, first: first, second: second)
    }

    @Test("A5: a workout whose set cannot be read is still listed, with its stored totals, though recent leaves it out")
    func damagedSet_stillLists() async throws {
        let damaged = try await Self.damaged("""
        UPDATE logged_set SET weight_e7g = 'heavy' WHERE workout_exercise_id IN
            (SELECT id FROM workout_exercise WHERE workout_id = ?)
        """)
        let listed = try await damaged.stack.workouts.historyEntries()
        #expect(listed.map(\.id) == [damaged.second.id, damaged.first.id])
        #expect(listed.first?.volume == damaged.second.volume, "the stored total, not a recomputation")
        let recent = try await damaged.stack.workouts.recent(limit: 10)
        #expect(
            recent.map(\.id) == [damaged.first.id],
            "the full read leaves the damaged workout out (the narrower rule)"
        )
    }

    @Test("A5: a workout whose own row cannot be read is left out, and the observation keeps running")
    func damagedRow_leftOut_observationRuns() async throws {
        let damaged = try await Self.damaged("UPDATE workout SET started_at = 'soon' WHERE id = ?")
        let observed = LibraryArrivals(damaged.stack.workouts.observeHistoryEntries())
        defer { observed.cancel() }
        let initial = await observed.next(within: .seconds(5))
        #expect(initial?.map(\.id) == [damaged.first.id])
        try await damaged.stack.workouts.delete(id: damaged.first.id)
        #expect(await observed.next(within: .seconds(5)) == [], "the stream did not end on the damaged row")
    }
}
