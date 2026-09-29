import Foundation
import LedgerDomain

/// A deliberately naive second implementation of the F04 reduction rules, for the model-based test
/// (criterion 10). It is written from the brief and F04's implementation notes, not from the engine.
///
/// It never calls `WorkoutEngine` or `SupersetRounds`. Instead it:
/// - edits one `WorkoutState` in place;
/// - finds a superset block by walking the `isSupersetWithPrevious` flags;
/// - rebuilds the block's rounds with plain loops on every call;
/// - caps every rest it writes at `restLimit`, spelled out below;
/// - ignores effects.
public struct ModelOracle: Sendable {
    public private(set) var state: WorkoutState?

    public init() {}

    /// Applies one envelope, in the order given.
    public mutating func apply(_ envelope: EventEnvelope) {
        guard let current = state else {
            state = Self.snapshot(startedBy: envelope)
            return
        }
        guard current.phase == .live, current.id == envelope.workoutID else {
            return
        }
        var model = Model(workout: current, time: envelope.wallClock)
        model.apply(envelope.event)
        state = model.workout
    }

    /// Replays a log: sorts it by (wall clock, device `uuidString`, seq), keeps only the workout the
    /// first usable `started` begins, keeps the first copy of each (device, seq) among those, applies
    /// that `started`, then everything else in order.
    ///
    /// The workout filter comes first because a (device, seq) pair repeats across workouts.
    public static func replay(_ log: [EventEnvelope]) -> WorkoutState? {
        let sorted = log.sorted(by: precedes)
        let workout = sorted.first { snapshot(startedBy: $0) != nil }?.workoutID
        var unique: [EventEnvelope] = []
        for envelope in sorted where envelope.workoutID == workout {
            if !unique.contains(where: { sameKey($0, envelope) }) {
                unique.append(envelope)
            }
        }
        var oracle = ModelOracle()
        if let first = unique.firstIndex(where: { snapshot(startedBy: $0) != nil }) {
            oracle.apply(unique.remove(at: first))
        }
        for envelope in unique {
            oracle.apply(envelope)
        }
        return oracle.state
    }

    /// The envelope order, spelled out as in the F04 brief.
    public static func precedes(_ lhs: EventEnvelope, _ rhs: EventEnvelope) -> Bool {
        if lhs.wallClock != rhs.wallClock {
            return lhs.wallClock < rhs.wallClock
        }
        if lhs.device != rhs.device {
            return lhs.device.rawValue.uuidString < rhs.device.rawValue.uuidString
        }
        return lhs.seq < rhs.seq
    }

    private static func sameKey(_ lhs: EventEnvelope, _ rhs: EventEnvelope) -> Bool {
        lhs.device == rhs.device && lhs.seq == rhs.seq
    }

    /// The live snapshot a valid `started` envelope carries.
    private static func snapshot(startedBy envelope: EventEnvelope) -> WorkoutState? {
        guard case let .started(snapshot) = envelope.event,
              snapshot.phase == .live,
              snapshot.id == envelope.workoutID
        else {
            return nil
        }
        return snapshot
    }
}

/// The rules as plain edits of one live workout. `time` is the envelope's wall clock. Internal, not
/// private, only so its per-row edits can live in `ModelOracle+Edits.swift`.
struct Model {
    /// A row: `exercises[exercise].sets[set]`.
    struct Row: Equatable {
        let exercise: Int
        let set: Int
    }

    var workout: WorkoutState
    let time: Date

    mutating func apply(_ event: WorkoutEvent) {
        switch event {
        case let .setLogged(exerciseIndex, setID, weight, reps, doneAt):
            logSet(exerciseIndex, setID, weight, reps, doneAt)
        case let .restStarted(endsAt, total):
            setRest(endsAt: endsAt, total: total, from: time)
        case let .restExtended(amount):
            extendRest(by: amount)
        case .restSkipped:
            workout.rest = nil
        case let .finished(endedAt):
            end(as: .finished, at: endedAt)
        case let .discarded(endedAt):
            end(as: .discarded, at: endedAt)
        default:
            editRows(event)
        }
    }

    mutating func editRows(_ event: WorkoutEvent) {
        switch event {
        case let .exerciseSelected(exerciseIndex, setIndex):
            select(exerciseIndex, setIndex)
        case let .setUnlogged(exerciseIndex, setID):
            if let setIndex = find(setID, in: exerciseIndex) {
                workout.exercises[exerciseIndex].sets[setIndex].doneAt = nil
            }
        case let .setTargetChanged(exerciseIndex, setID, weight, reps):
            changeTarget(exerciseIndex, setID, weight, reps)
        case let .setAdded(exerciseIndex, set):
            addSet(exerciseIndex, set)
        case let .allSetsRepeated(exerciseIndex, weight, reps):
            repeatAll(exerciseIndex, weight, reps)
        case let .exerciseSwapped(exerciseIndex, exerciseID, name, alsoUpdateProgram):
            swap(exerciseIndex, exerciseID, name, alsoUpdateProgram)
        default:
            break // a second `started` is ignored; `apply` handles every other event
        }
    }

    mutating func logSet(_ exerciseIndex: Int, _ setID: SetID, _ weight: Weight, _ reps: Reps, _ doneAt: Date) {
        guard let setIndex = find(setID, in: exerciseIndex) else {
            return
        }
        let wasDone = workout.exercises[exerciseIndex].sets[setIndex].doneAt != nil
        workout.exercises[exerciseIndex].sets[setIndex].weight = weight < .zero ? .zero : weight
        workout.exercises[exerciseIndex].sets[setIndex].reps = reps
        workout.exercises[exerciseIndex].sets[setIndex].doneAt = doneAt
        if wasDone {
            return
        }
        let members = blockMembers(of: exerciseIndex)
        let rounds = buildRounds(of: members)
        let row = Row(exercise: exerciseIndex, set: setIndex)
        if workout.autoRest, rounds.contains(where: { $0.last == row }) {
            var longest = 0
            for member in members {
                longest = max(longest, workout.exercises[member].rest.seconds)
            }
            let total = Duration.seconds(longest)
            setRest(endsAt: doneAt.addingTimeInterval(total / .seconds(1)), total: total, from: doneAt)
        }
        if let next = nextRow(after: row, members: members, rounds: rounds) {
            workout.cursor = Cursor(exerciseIndex: next.exercise, setIndex: next.set)
        }
    }

    /// Rule 20, spelled out: later undone rows, then earlier undone rows, then the next block's first row.
    func nextRow(after row: Row, members: [Int], rounds: [[Row]]) -> Row? {
        let order = rounds.flatMap(\.self)
        guard let position = order.firstIndex(of: row) else {
            return nil
        }
        for candidate in order[(position + 1)...] where isUndone(candidate) {
            return candidate
        }
        for candidate in order[..<position] where isUndone(candidate) {
            return candidate
        }
        let nextExercise = (members.last ?? row.exercise) + 1
        guard nextExercise < workout.exercises.count else {
            return nil
        }
        return buildRounds(of: blockMembers(of: nextExercise)).first?.first
    }

    func isUndone(_ row: Row) -> Bool {
        workout.exercises[row.exercise].sets[row.set].doneAt == nil
    }

    /// The exercises of `exerciseIndex`'s superset block, found by walking the flags both ways.
    func blockMembers(of exerciseIndex: Int) -> [Int] {
        var first = exerciseIndex
        while first > 0, workout.exercises[first].isSupersetWithPrevious {
            first -= 1
        }
        var last = exerciseIndex
        while last + 1 < workout.exercises.count, workout.exercises[last + 1].isSupersetWithPrevious {
            last += 1
        }
        return Array(first ... last)
    }

    /// Round r holds each member's r-th non-drop row; then the drop rows form rounds of their own.
    func buildRounds(of members: [Int]) -> [[Row]] {
        var result: [[Row]] = []
        for dropRounds in [false, true] {
            var round = 0
            while true {
                var rows: [Row] = []
                for member in members {
                    let sets = workout.exercises[member].sets
                    let matching = sets.indices.filter { (sets[$0].kind == .drop) == dropRounds }
                    if round < matching.count {
                        rows.append(Row(exercise: member, set: matching[round]))
                    }
                }
                if rows.isEmpty {
                    break
                }
                result.append(rows)
                round += 1
            }
        }
        return result
    }
}
