import Foundation
import LedgerDomain
import LedgerTestSupport

extension Program {
    /// This program with slot `id` changed by `change`; as it is when it holds no such slot.
    func changing(_ id: SlotID, _ change: (inout Slot) -> Void) -> Program {
        var changed = self
        for day in changed.days.indices {
            for slot in changed.days[day].slots.indices where changed.days[day].slots[slot].id == id {
                change(&changed.days[day].slots[slot])
            }
        }
        return changed
    }

    var slotIDs: [SlotID] {
        days.flatMap(\.slots).map(\.id)
    }
}

/// F10 S3's criteria 1 to 4 as a model, written from the brief: what a save leaves in the programs, in history
/// and in the logs. It knows nothing of rows, records or refusals; the scripts give it only workouts a store
/// accepts.
struct LinkedModel {
    var exercises: Set<ExerciseID>
    /// The programs that are stored and not deleted.
    var programs: [ProgramID: Program]
    var history: Set<WorkoutID> = []
    /// How many envelopes each stored log holds.
    var logs: [WorkoutID: Int] = [:]

    init(programs: [Program]) {
        exercises = Set(LinkedFixture.exercises.map(\.id))
        self.programs = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
    }

    /// Criteria 1, 2 and 4. Returns whether the log went with the save: linked stores answer what was asked.
    mutating func save(_ workout: WorkoutState, slots: [Slot], droppingLog: Bool) -> Bool {
        history.insert(workout.id)
        // Rule 13, as before S3: a listed slot that is stored takes the listed misses, whole.
        for slot in slots {
            for (id, program) in programs {
                programs[id] = program.changing(slot.id) { $0.misses = slot.misses }
            }
        }
        // Criteria 1 and 2: only a stored slot of the workout's own program, only a stored exercise.
        if let own = workout.source?.programID, let program = programs[own] {
            var updated = program
            for (slot, exercise) in workout.programUpdates where exercises.contains(exercise) {
                updated = updated.changing(slot) { $0.exerciseID = exercise }
            }
            programs[own] = updated
        }
        if droppingLog {
            logs[workout.id] = nil
        }
        return droppingLog
    }

    /// `nil` when `stores` hold what the model holds, else the first difference in a line.
    func difference(from stores: LinkedStores) async throws -> String? {
        for number in [1, 2] {
            let stored = try await stores.program(number)
            if let line = LinkedDifference.of(stored, programs[S2Kit.programID(number)], "program \(number)") {
                return line
            }
        }
        let saved = try await Set(stores.workouts.recent(limit: 10000).map(\.id))
        guard saved == history else {
            return "history holds \(saved.count) workouts, the model \(history.count)"
        }
        let kept = try await Set(stores.events.uncompactedWorkoutIDs())
        guard kept == Set(logs.keys) else {
            return "\(kept.count) logs are stored, the model has \(logs.count)"
        }
        for (workout, count) in logs {
            let stored = try await stores.events.envelopes(for: workout).count
            if stored != count {
                return "a log holds \(stored) envelopes, the model \(count)"
            }
        }
        return nil
    }
}

/// What two kinds of store hold, compared through their protocols: `nil` when they agree.
enum LinkedComparison {
    static func difference(_ one: LinkedStores, _ other: LinkedStores) async throws -> String? {
        for number in [1, 2] {
            let (first, second) = try await (one.program(number), other.program(number))
            if let line = LinkedDifference.of(first, second, "program \(number), \(one.kind) against \(other.kind)") {
                return line
            }
        }
        let (saved, expected) = try await (one.workouts.recent(limit: 10000), other.workouts.recent(limit: 10000))
        guard saved == expected else {
            return "history: \(one.kind) holds \(saved.count) workouts, \(other.kind) \(expected.count), or they differ"
        }
        let (kept, wanted) = try await (
            Set(one.events.uncompactedWorkoutIDs()), Set(other.events.uncompactedWorkoutIDs())
        )
        guard kept == wanted else {
            return "logs: \(one.kind) keeps \(kept.count), \(other.kind) \(wanted.count)"
        }
        for workout in kept {
            let (first, second) = try await (one.events.envelopes(for: workout), other.events.envelopes(for: workout))
            if Set(first) != Set(second) {
                return "a log differs: \(first.count) envelopes against \(second.count)"
            }
        }
        return nil
    }
}
