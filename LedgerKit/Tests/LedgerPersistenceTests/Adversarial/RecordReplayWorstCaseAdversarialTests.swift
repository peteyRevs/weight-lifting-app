import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 records follow-up, adversarial round 1: product decision #27's replay in shapes worse than the
/// implementer's (`RecordReplayPerformanceTests`), each still 20,000 sets in 400 workouts. Finding R-1: on both
/// simulators every shape was over the 50 ms stats budget; the orchestrator gave History writes a budget of their
/// own (`PerformanceBudget.historyWrite`, architecture §15; sanctioned edit, budget only). Nightly lane only, like
/// every timing test.
@Suite(
    "Adversarial records · replay timing, worse shapes",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .serialized,
    .timeLimit(.minutes(5))
)
struct RecordReplayWorstCaseAdversarialTests {
    enum Shape: String, CaseIterable, Sendable {
        /// One lift, 50 sets a workout; the typo is a 12-rep set, the ceiling of every rep count, so both the
        /// estimate and the weight record of all 399 later workouts go, and come back.
        case oneLiftBothRecords
        /// Five lifts of 10 sets a workout; the first workout is rebuilt with a typo in each lift's 10-rep set, so
        /// the replay walks five exercises and 3,990 records flip.
        case fiveLiftsRebuild
        /// Five lifts of 10 sets a workout; a forgotten light session of all five lands before the first workout
        /// and is deleted again, so each write walks five exercises over 400 workouts while only ten records
        /// change (the first workout's, which now beats it).
        case fiveLiftsLateWorkout
        /// The realistic one: five lifts of 10 sets a workout, each lift five sets of 5 and five of 8 reps (two
        /// rep counts, not ten), and the lifter deletes the first workout from History, then it is stored again.
        case fiveLiftsDeleteFirst
    }

    static let lifts = (1 ... 5).map(S3Kit.exerciseID)

    static func workout(_ number: Int, lifts: Int, typo: Bool = false, twoRepCounts: Bool = false) -> WorkoutState {
        let perLift = 50 / lifts
        let rows = (0 ..< lifts).map { lift in
            S3Kit.RowSpec(Self.lifts[lift], (0 ..< perLift).map { set in
                if twoRepCounts {
                    return S3Kit.set(Decimal(number + set + 1) * 2.5, set < 5 ? 5 : 8)
                }
                let typoHere = typo && set == min(perLift, 12) - 1 // the most reps: every rep count's ceiling
                return S3Kit.set(typoHere ? 2250 : Decimal(number + set + 1) * 2.5, 1 + set % 12)
            })
        }
        return S3Kit.workout(
            number,
            endedAt: S3Kit.now.addingTimeInterval(3600 * Double(number - 399)),
            minutes: 30,
            rows
        )
    }

    /// Five lifts at 1 lb, an hour before the first workout.
    static var forgotten: WorkoutState {
        let rows = lifts.map { S3Kit.RowSpec($0, (0 ..< 10).map { S3Kit.set(1, 1 + $0) }) }
        return S3Kit.workout(999, endedAt: S3Kit.now.addingTimeInterval(-3600 * 400), minutes: 30, rows)
    }

    /// The shape's write: odd runs make the change, even ones undo it.
    static func write(_ shape: Shape, change: Bool, _ workouts: GRDBWorkoutRepository) async throws {
        let liftCount = shape == .oneLiftBothRecords ? 1 : 5
        let first = workout(0, lifts: liftCount, twoRepCounts: shape == .fiveLiftsDeleteFirst)
        let typo = workout(0, lifts: liftCount, typo: true)
        switch shape {
        case .oneLiftBothRecords:
            let sets = (change ? typo : first).exercises[0].sets
            try await workouts.updateSets(workoutExerciseID: first.exercises[0].id, sets: sets)
        case .fiveLiftsRebuild:
            try await workouts.materialize(change ? typo : first, slotUpdates: [])
        case .fiveLiftsDeleteFirst:
            if change {
                try await workouts.delete(id: first.id)
            } else {
                try await workouts.materialize(first, slotUpdates: [])
            }
        case .fiveLiftsLateWorkout:
            if change {
                try await workouts.materialize(forgotten, slotUpdates: [])
            } else {
                try await workouts.delete(id: forgotten.id)
            }
        }
    }

    /// The first lift's records after the write.
    static func records(_ shape: Shape, change: Bool) -> Int {
        switch shape {
        case .fiveLiftsLateWorkout: 399 * 2 + (change ? 2 : 0)
        case .fiveLiftsDeleteFirst: change ? 398 * 2 : 399 * 2
        case .oneLiftBothRecords, .fiveLiftsRebuild: change ? 0 : 399 * 2
        }
    }

    @Test(
        "Each worse shape's write is within the History write budget (95th percentile of 20)",
        arguments: Shape.allCases
    )
    func worseShape_underBudget(shape: Shape) async throws {
        let directory = TemporaryDirectory("\(#function)\(shape.rawValue)")
        defer { try? directory.remove() } // cleanup only
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let workouts = GRDBWorkoutRepository(queue, now: { S3Kit.now })
        let stats = GRDBStatsQueries(queue, now: { S3Kit.now })
        let liftCount = shape == .oneLiftBothRecords ? 1 : 5
        for number in 0 ..< 400 {
            let stored = Self.workout(number, lifts: liftCount, twoRepCounts: shape == .fiveLiftsDeleteFirst)
            try await workouts.materialize(stored, slotUpdates: [])
        }
        let clock = ContinuousClock()
        var timings: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            let change = run.isMultiple(of: 2)
            try await timings.append(clock.measure { try await Self.write(shape, change: change, workouts) })
            let records = try await stats.personalRecords(exerciseID: Self.lifts[0]).count
            #expect(records == Self.records(shape, change: change), "run \(run)")
        }
        timings.removeFirst()
        let sorted = timings.sorted()
        let p95 = sorted[sorted.count * 95 / 100 - 1]
        Attachment.record("\(shape): p95 \(p95), median \(sorted[sorted.count / 2])", named: "replay-\(shape).txt")
        #expect(p95 < PerformanceBudget.historyWrite, "\(shape): \(timings)")
    }
}
