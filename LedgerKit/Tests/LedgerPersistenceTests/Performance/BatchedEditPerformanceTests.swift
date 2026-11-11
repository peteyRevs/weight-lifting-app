import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S3, R5: a batched edit of three exercises of the first of 400 workouts, with the list's and the detail's
/// observers running, in the History write's budget (architecture §15). Nightly lane only, as its parent suite.
extension RecordReplayPerformanceTests {
    /// The first workout with its lift three times under new ids, so an edit names three exercises.
    private static func firstWithThreeExercises() -> WorkoutState {
        var first = workout(0)
        let lift = first.exercises[0]
        first.exercises = (0 ..< 3).map { place in
            let sets = lift.sets.enumerated().map { index, set in
                LoggedSet(
                    id: SetID(UUID(uuidString: "00000000-0000-0000-0000-0000000F13\(place)\(index)") ?? UUID()),
                    weight: set.weight,
                    reps: set.reps,
                    kind: set.kind,
                    doneAt: set.doneAt
                )
            }
            return WorkoutExercise(
                id: WorkoutExerciseID(UUID(uuidString: "00000000-0000-0000-0000-00000000F13\(place)") ?? UUID()),
                slotID: nil,
                exerciseID: lift.exerciseID,
                originalExerciseID: lift.originalExerciseID,
                name: lift.name,
                equipment: lift.equipment,
                step: lift.step,
                rest: lift.rest,
                rpe: lift.rpe,
                isSupersetWithPrevious: false,
                targetSets: lift.targetSets,
                targetReps: lift.targetReps,
                targetLoad: lift.targetLoad,
                sets: sets
            )
        }
        return first
    }

    @Test("A batched edit of three exercises, with the list and the detail observing, within budget")
    func batchedEditOfThree_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await Self.seeded(in: directory)
        let workouts = GRDBWorkoutRepository(queue, now: { Self.now })
        let edited = Self.firstWithThreeExercises()
        try await workouts.materialize(edited, slotUpdates: [])
        let (entries, recorded) = (workouts.observeHistoryEntries(), workouts.observeWorkout(id: edited.id))
        let list = Task { for await _ in entries {} }
        let detail = Task { for await _ in recorded {} }
        defer {
            list.cancel()
            detail.cancel()
        }
        let clock = ContinuousClock()
        var edits: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            let pounds: Decimal = run.isMultiple(of: 2) ? 2250 : 2255
            var map: [WorkoutExerciseID: [LoggedSet]] = [:]
            for exercise in edited.exercises {
                var sets = exercise.sets
                sets[0].weight = .pounds(pounds)
                map[exercise.id] = sets
            }
            try await edits.append(clock.measure { try await workouts.updateSets(map, of: edited.id) })
        }
        let runs = Array(edits.dropFirst())
        #expect(Self.percentile95(runs) < PerformanceBudget.historyWrite, "\(runs)")
    }
}
