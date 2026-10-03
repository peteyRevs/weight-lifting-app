import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: the GRDB repository and stats queries against `HistoryModel` over random
/// histories. After every operation both must have thrown the same error or neither, and every read and
/// every stats query must agree, under a random time zone, week start and current time.
@Suite("Adversarial S3 · history against a model", .tags(.persistence, .property), .timeLimit(.minutes(5)))
struct HistoryModelAdversarialTests {
    /// Sixty scripts in the PR lane; every seed of `LEDGER_PROPERTY_SEED_COUNT` in the nightly one.
    static let seeds = TestLane.runsSlowTests ? PropertySeed.all : Array(PropertySeed.all.prefix(60))
    /// The seeds a faulty model is tried on.
    static let faultSeeds = Array(PropertySeed.all.prefix(60))

    /// What both sides did with one operation: nothing thrown, or the error.
    static func outcome(_ body: () async throws -> Void) async -> String {
        do {
            try await body()
            return "ok"
        } catch {
            return "threw \(error)"
        }
    }

    static func apply(_ operation: HistoryScript.Operation, to workouts: any WorkoutRepository) async -> String {
        await outcome {
            switch operation {
            case let .materialize(workout):
                try await workouts.materialize(workout, slotUpdates: [])
            case let .updateSets(row, sets):
                try await workouts.updateSets(workoutExerciseID: row, sets: sets)
            case let .delete(id):
                try await workouts.delete(id: id)
            }
        }
    }

    /// Every read of the repository, labelled.
    static func reads(_ workouts: any WorkoutRepository, _ script: HistoryScript) async throws -> [String] {
        var lines: [String] = []
        for limit in [-1, 0, 1, 3, 100] {
            try await lines.append("recent(\(limit)): \(workouts.recent(limit: limit))")
        }
        for number in 1 ... 6 {
            try await lines
                .append("workout(\(number)): \(String(describing: workouts.workout(id: S3Kit.workoutID(number))))")
        }
        let week = script.calendar.week(containing: script.now)
        for range in [
            week,
            .distantPast ..< week.lowerBound,
            week.upperBound ..< .distantFuture,
            script.now ..< script.now
        ] {
            try await lines.append("workouts(in: \(range)): \(workouts.workouts(in: range))")
        }
        return lines
    }

    /// Every stats query, labelled.
    static func stats(_ stats: any StatsQueries, _ script: HistoryScript) async throws -> [String] {
        var lines: [String] = []
        let week = script.calendar.week(containing: script.now)
        let previous = script.calendar.previousCompleteWeek(before: script.now)
        for exercise in HistoryScript.exercises {
            let best = try await stats.bestSet(exerciseID: exercise)
            try await lines.append("last: \(String(describing: stats.lastPerformance(exerciseID: exercise)))")
            lines.append("bestSet: \(String(describing: best?.weight)) × \(String(describing: best?.reps))")
            try await lines.append("bestE1RM: \(String(describing: stats.bestE1RM(exerciseID: exercise)))")
            for weeks in [0, 1, 2, 8, 100, Int.max] {
                let byWeek = try await stats.e1RMByWeek(
                    exerciseID: exercise,
                    lastWeeks: weeks,
                    calendar: script.calendar
                )
                lines.append("e1RMByWeek(\(weeks)): \(byWeek.sorted { $0.key < $1.key })")
            }
            try await lines.append("sessionCount: \(stats.sessionCount(exerciseID: exercise))")
            try await lines.append("records: \(stats.personalRecords(exerciseID: exercise))")
        }
        for range in [week, previous, .distantPast ..< .distantFuture, script.now ..< script.now] {
            try await lines.append("volume(\(range)): \(stats.weeklyVolume(in: range))")
            try await lines.append("sessions(\(range)): \(stats.sessionsCompleted(in: range))")
        }
        for limit in [-1, 0, 1, 2, 10] {
            try await lines.append("recentlyLogged(\(limit)): \(stats.recentlyLogged(limit: limit))")
        }
        return lines
    }

    /// `bests(before:for:)` before each of `workouts` and before a workout that is not stored, starting at the
    /// script's `now`, for every exercise of the script (F05 records follow-up, product decision #27). Each
    /// answer is spelled with its keys in order, so two equal answers read the same.
    static func bests(
        _ stats: any StatsQueries,
        before workouts: [WorkoutState],
        _ script: HistoryScript
    ) async throws -> [String] {
        let probe = S3Kit.workout(99, endedAt: script.now, minutes: 0, [])
        var lines: [String] = []
        for workout in workouts + [probe] {
            let bests = try await stats.bests(before: workout, for: Set(HistoryScript.exercises))
            let e1RM = bests.e1RM.sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
            let weights = bests.weightAtReps.sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
                .map { ($0.key, $0.value.sorted { $0.key < $1.key }) }
            lines.append("bests(before: \(workout.id)): \(e1RM) \(weights)")
        }
        return lines
    }

    /// Runs seed's script against the database and a model with `faults`: the first disagreement, or `nil`.
    static func firstMismatch(_ seed: PropertySeed, faults: Set<HistoryModel.Fault> = []) async throws -> String? {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let model = HistoryModel(faults: faults, now: script.now)
        let stats = stack.stats(now: script.now)
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            let before = try await stack.dump()
            let stored = await apply(operation, to: stack.workouts)
            let expected = await apply(operation, to: model)
            guard stored == expected else {
                return "step \(step), \(operation): \(stored), expected \(expected)"
            }
            if stored != "ok", try await stack.dump() != before {
                return "step \(step): a refused call changed rows"
            }
            let live = try await stack.workouts.recent(limit: 100)
            let actual = try await reads(stack.workouts, script) + Self.stats(stats, script)
                + bests(stats, before: live, script)
            let wanted = try await reads(model, script) + Self.stats(model, script)
                + bests(model, before: live, script)
            if let mismatch = zip(actual, wanted).first(where: { $0 != $1 }) {
                return "step \(step): got \(mismatch.0), expected \(mismatch.1)"
            }
        }
        return nil
    }

    @Test(
        "Random materialisations, edits and deletes: every outcome, read and stats query matches the model",
        arguments: seeds
    )
    func randomHistory_matchesTheModel(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }

    /// The faults this script cannot show: it has no live-only fields, no slots and no observation.
    static let unseen: Set<HistoryModel.Fault> = [.keepsLiveFields, .missesAreMerged, .emitsEveryWrite]

    /// Nightly lane only: it runs up to 60 scripts for each of 22 faults, and guards the test above, not the
    /// product.
    @Test(
        "The model test bites: a model with any one fault disagrees with the database within these seeds",
        .tags(.slow),
        .enabled(if: TestLane.runsSlowTests, "a .slow test: nightly lane only"),
        arguments: HistoryModel.Fault.allCases.filter { !unseen.contains($0) }
    )
    func faultyModel_disagrees(fault: HistoryModel.Fault) async throws {
        var found = false
        for seed in Self.faultSeeds where !found {
            found = try await Self.firstMismatch(seed, faults: [fault]) != nil
        }
        #expect(found, "no seed shows \(fault.rawValue)")
    }
}
