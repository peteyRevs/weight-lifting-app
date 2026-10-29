import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S2 adversarial (G2): `observeWorkout(id:)`, the detail's one observation (N8), where the three contract
/// clauses are silent. Random finishes, edits and deletes (F05's `HistoryScript`) run on GRDB and in memory while all
/// six of the script's workouts are observed on GRDB: after every step each read agrees with the fake's (records and
/// their order included), and each stream has emitted exactly the values that changed, once. And a delete of a
/// record holder hands its records to the next workout (records recompute). Writes and damage:
/// `WorkoutDetailDamageAdversarialTests`.
@Suite(
    "Adversarial F13 S2 · observeWorkout on GRDB and in memory",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct WorkoutDetailObservationAdversarialTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(24))
    static let numbers = Array(1 ... 6)

    static func describe(_ value: RecordedWorkout??) -> String {
        guard let found = value else {
            return "no value"
        }
        guard let recorded = found else {
            return "nil"
        }
        let records = recorded.records.map { "\($0.exerciseID.rawValue.uuidString.suffix(4)) \($0.kind)" }
        let rows = recorded.workout.exercises.count
        return "\(recorded.workout.name) \(rows) rows, records [\(records.joined(separator: ", "))]"
    }

    /// GRDB's one-shot read of workout `number`.
    static func read(_ number: Int, in stack: S3Kit.Stack) async throws -> RecordedWorkout? {
        try await stack.queue.read { database in
            try GRDBWorkoutRepository.fetchRecordedWorkout(S3Kit.workoutID(number), in: database)
        }
    }

    /// The fake's value of workout `number` now.
    static func faked(_ number: Int, in fakes: InMemoryStores) async -> RecordedWorkout? {
        var values = fakes.workouts.observeWorkout(id: S3Kit.workoutID(number)).makeAsyncIterator()
        return await values.next() ?? nil
    }

    /// One script run: GRDB and the fake, and each of the six workouts' GRDB stream with its last value.
    struct Run {
        let stack: S3Kit.Stack
        let fakes: InMemoryStores
        let streams: [LibraryArrivals<RecordedWorkout?>]
        var shown: [RecordedWorkout?]
        var withRecords = 0

        /// How workout `number` disagrees after a step: GRDB with the fake, or its stream with GRDB's read.
        mutating func mismatch(_ index: Int) async throws -> String? {
            let number = numbers[index]
            let stored = try await read(number, in: stack)
            let faked = await faked(number, in: fakes)
            guard stored == faked else {
                return "workout \(number): GRDB \(describe(stored)), fake \(describe(faked))"
            }
            withRecords += (stored?.records.count ?? 0) > 1 ? 1 : 0
            guard stored != shown[index] else {
                return nil
            }
            let value = await streams[index].next(within: .seconds(5))
            guard let value, value == stored else {
                return "workout \(number): observed \(describe(value)), read \(describe(stored))"
            }
            shown[index] = stored
            return nil
        }
    }

    /// The first disagreement of `seed`'s script, and how many steps had a workout with records to compare.
    static func firstMismatch(_ seed: PropertySeed) async throws -> (mismatch: String?, withRecords: Int) {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let now = script.now
        let streams = Self.numbers.map { LibraryArrivals(stack.workouts.observeWorkout(id: S3Kit.workoutID($0))) }
        defer { streams.forEach { $0.cancel() } }
        var run = Run(stack: stack, fakes: InMemoryStores(now: { now }), streams: streams, shown: [])
        for stream in streams {
            let first = await stream.next(within: .seconds(5))
            guard let first, first == nil else {
                return ("the first value of an empty database is \(describe(first))", 0)
            }
            run.shown.append(nil)
        }
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            _ = await History.apply(operation, to: stack.workouts)
            _ = await History.apply(operation, to: run.fakes.workouts)
            for index in Self.numbers.indices {
                if let mismatch = try await run.mismatch(index) {
                    return ("step \(step), \(operation), \(mismatch)", run.withRecords)
                }
            }
        }
        for (index, stream) in streams.enumerated() {
            if let extra = await stream.next(within: .milliseconds(150)) {
                return ("workout \(Self.numbers[index]): a value no read changed, \(describe(extra))", run.withRecords)
            }
        }
        return (nil, run.withRecords)
    }

    @Test("Random finishes, edits and deletes: each workout's value is the fake's, and is observed once per change")
    func observeWorkout_agreesWithTheFake_andEmitsOncePerChange() async throws {
        var proving = 0
        for seed in Self.seeds {
            let (mismatch, withRecords) = try await Self.firstMismatch(seed)
            #expect(mismatch == nil, "\(seed)")
            proving += withRecords > 0 ? 1 : 0
        }
        // Some scripts must compare a workout holding two records or more, or the record order is not attacked (a
        // first session of a lift holds none, so most short scripts hold few).
        #expect(proving >= 4, "only \(proving) of \(Self.seeds.count) scripts held two records")
    }

    // MARK: - Records recompute after a delete

    @Test("Deleting the record holder hands its records to the next workout, whose detail is told")
    func deletingTheHolder_movesItsRecordsToTheNextWorkout() async throws {
        let stack = try await S3Kit.stack()
        // A lift's first session holds no record (nothing stands before it), so a baseline comes first.
        let baseline = S3Kit.workout(4, endedAt: S3Kit.day(-4), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(150, 5)])])
        let holder = S3Kit.workout(1, endedAt: S3Kit.day(-3), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(225, 5)])])
        let middle = S3Kit.workout(2, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 5)])])
        let latest = S3Kit.workout(3, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(210, 5)])])
        for workout in [baseline, holder, middle, latest] {
            try await stack.materialize(workout)
        }
        let middleValues = LibraryArrivals(stack.workouts.observeWorkout(id: middle.id))
        let latestValues = LibraryArrivals(stack.workouts.observeWorkout(id: latest.id))
        defer {
            middleValues.cancel()
            latestValues.cancel()
        }
        let middleBefore = await middleValues.next(within: .seconds(5))
        let latestBefore = await latestValues.next(within: .seconds(5))
        #expect(middleBefore??.records == [], "225 stands over 200")
        #expect(latestBefore??.records == [], "225 stands over 210")

        try await stack.workouts.delete(id: holder.id)
        let middleAfter = await middleValues.next(within: .seconds(5))
        let latestAfter = await latestValues.next(within: .seconds(5))
        let middleKinds = middleAfter??.records.map(\.kind) ?? []
        let latestKinds = latestAfter??.records.map(\.kind) ?? []
        #expect(middleKinds.count == 2, "200 now beats the baseline's 150: an estimated 1RM and a weight at 5")
        #expect(latestKinds.count == 2, "210 beats 200 on both")
        let stats = stack.stats()
        let listed = try await stats.personalRecords(exerciseID: S3Kit.bench)
        let holders = Set(listed.map(\.workoutID))
        #expect(holders == [middle.id, latest.id])
        let entries = try await stack.workouts.historyEntries()
        #expect(entries.map(\.prCount) == [2, 2, 0], "the list's badges follow")
    }

    @Test("Records of two lifts come in the same order from GRDB and from the fake")
    func manyRecords_sameOrderOnBoth() async throws {
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores(now: { S3Kit.now })
        let baseline = S3Kit.workout(1, endedAt: S3Kit.day(-2), [
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(100, 3), S3Kit.set(100, 5), S3Kit.set(100, 8)]),
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 3), S3Kit.set(100, 5), S3Kit.set(100, 8)])
        ])
        let mine = S3Kit.workout(2, endedAt: S3Kit.day(-1), [
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(105, 8), S3Kit.set(120, 3), S3Kit.set(110, 5)]),
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(110, 5), S3Kit.set(105, 8), S3Kit.set(120, 3)])
        ])
        for workout in [baseline, mine] {
            try await stack.materialize(workout)
            try await fakes.workouts.materialize(workout, slotUpdates: [])
        }
        let stored = try await Self.read(2, in: stack)
        let faked = await Self.faked(2, in: fakes)
        #expect(
            stored?.records.count == 4,
            "an estimated 1RM and one weight at reps per lift: \(Self.describe(stored))"
        )
        let isTheSame = stored == faked
        #expect(isTheSame, "GRDB \(Self.describe(stored)), fake \(Self.describe(faked))")
    }
}
