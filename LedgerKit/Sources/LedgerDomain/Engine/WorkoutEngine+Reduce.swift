import Foundation

extension WorkoutEngine {
    /// Applies one event to a live state in place (rules 3–11) and returns the event's own effects, or
    /// `nil` when the event is ignored outright (rule 1: a second `started`). `time` is the envelope's
    /// `wallClock`, the time of events that carry none.
    static func apply(_ event: WorkoutEvent, to state: inout WorkoutState?, at time: Date) -> [Effect]? {
        switch event {
        case .started:
            nil
        case let .exerciseSelected(exerciseIndex, setIndex):
            state?.select(exerciseIndex, setIndex)
        case let .setLogged(exerciseIndex, setID, weight, reps, doneAt):
            state?.logSet(setID, of: exerciseIndex, weight: weight, reps: reps, doneAt: doneAt)
        case let .setUnlogged(exerciseIndex, setID):
            state?.editSet(setID, of: exerciseIndex) { $0.doneAt = nil }
        case let .setTargetChanged(exerciseIndex, setID, weight, reps):
            state?.changeTarget(setID, of: exerciseIndex, weight: weight, reps: reps)
        case let .setAdded(exerciseIndex, set):
            state?.add(set, to: exerciseIndex)
        case let .allSetsRepeated(exerciseIndex, weight, reps):
            state?.repeatAll(of: exerciseIndex, weight: weight, reps: reps)
        case let .exerciseSwapped(exerciseIndex, exerciseID, name, alsoUpdateProgram):
            state?.swap(exerciseIndex, to: exerciseID, name: name, inProgram: alsoUpdateProgram)
        case .restStarted, .restExtended, .restSkipped, .finished, .discarded:
            applyClockEvent(event, to: &state, at: time)
        }
    }

    /// Rules 9 and 10: the rest timer and the terminal events. Split from `apply`, which routes only
    /// these five cases here, to keep each switch within SwiftLint's complexity limit.
    private static func applyClockEvent(
        _ event: WorkoutEvent,
        to state: inout WorkoutState?,
        at time: Date
    ) -> [Effect]? {
        switch event {
        case let .restStarted(endsAt, total):
            state?.startRest(RestTimer(endsAt: endsAt, total: total), at: time)
        case let .restExtended(amount):
            state?.extendRest(by: amount, at: time)
        case .restSkipped:
            state?.skipRest()
        case let .finished(endedAt):
            state?.end(.finished, at: endedAt)
        case let .discarded(endedAt):
            state?.end(.discarded, at: endedAt)
        default:
            nil
        }
    }
}

// MARK: - The rules, as edits of a live state

private extension WorkoutState {
    typealias SetRef = SupersetRounds.SetRef

    /// Rule 11: the cursor moves to a row that exists and is not done; anything else is ignored.
    mutating func select(_ exerciseIndex: Int, _ setIndex: Int) -> [Effect] {
        guard exercises.indices.contains(exerciseIndex),
              exercises[exerciseIndex].sets.indices.contains(setIndex),
              !exercises[exerciseIndex].sets[setIndex].isDone
        else {
            return []
        }
        cursor = Cursor(exerciseIndex: exerciseIndex, setIndex: setIndex)
        return []
    }

    /// Rule 3: the set is done at `doneAt` with the logged values (the latest envelope wins). Only the
    /// not-done → done transition (rule 18) starts rest, for the last row of a round when auto rest is
    /// on (rule 19), and advances the cursor (rule 20). That rest starts at `doneAt`.
    mutating func logSet(_ id: SetID, of exerciseIndex: Int, weight: Weight, reps: Reps, doneAt: Date) -> [Effect] {
        guard let setIndex = row(of: id, in: exerciseIndex) else {
            return []
        }
        let wasDone = exercises[exerciseIndex].sets[setIndex].isDone
        exercises[exerciseIndex].sets[setIndex].weight = max(weight, .zero)
        exercises[exerciseIndex].sets[setIndex].reps = reps
        exercises[exerciseIndex].sets[setIndex].doneAt = doneAt
        let blocks = SupersetRounds.blocks(in: exercises)
        guard !wasDone, let blockIndex = blocks.firstIndex(where: { $0.exerciseIndices.contains(exerciseIndex) }) else {
            return [.haptic(.setLogged)]
        }
        let ref = SetRef(exerciseIndex: exerciseIndex, setIndex: setIndex)
        var effects: [Effect] = [.haptic(.setLogged)]
        if autoRest, SupersetRounds.isLastOfRound(ref, block: blocks[blockIndex], exercises: exercises) {
            let groupRest = SupersetRounds.groupRest(block: blocks[blockIndex], exercises: exercises).duration
            effects += startRest(RestTimer(endsAt: doneAt.adding(groupRest), total: groupRest), at: doneAt)
        }
        cursor = nextCursor(after: ref, blocks: blocks, blockIndex: blockIndex) ?? cursor
        return effects
    }

    /// Rule 20: the next undone row after `ref` in its block's display order, else the earliest
    /// undone row before it, else the first row of the next block; `nil` (stay) when there is none.
    func nextCursor(after ref: SetRef, blocks: [SupersetRounds.Block], blockIndex: Int) -> Cursor? {
        let order = SupersetRounds.displayOrder(block: blocks[blockIndex], exercises: exercises)
        let isUndone = { (row: SetRef) in !exercises[row.exerciseIndex].sets[row.setIndex].isDone }
        let nextBlock = blocks.dropFirst(blockIndex + 1).first
        let target = order.drop { $0 != ref }.dropFirst().first(where: isUndone)
            ?? order.prefix { $0 != ref }.first(where: isUndone)
            ?? nextBlock.flatMap { SupersetRounds.displayOrder(block: $0, exercises: exercises).first }
        return target.map { Cursor(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex) }
    }

    /// Rule 5: each given field overwrites the set's, so the latest envelope wins per field. A weight
    /// is never below zero (spec rule 1); reps are at least 1 by type.
    mutating func changeTarget(_ id: SetID, of exerciseIndex: Int, weight: Weight?, reps: Reps?) -> [Effect] {
        editSet(id, of: exerciseIndex) { set in
            if let weight {
                set.weight = max(weight, .zero)
            }
            if let reps {
                set.reps = reps
            }
        }
    }

    /// Rules 6 and 26: appends `set` as an undone `.added` row, once per set ID in the workout.
    mutating func add(_ set: LoggedSet, to exerciseIndex: Int) -> [Effect] {
        guard exercises.indices.contains(exerciseIndex),
              !exercises.contains(where: { $0.sets.contains { $0.id == set.id } })
        else {
            return []
        }
        let added = LoggedSet(id: set.id, weight: max(set.weight, .zero), reps: set.reps, kind: .added)
        exercises[exerciseIndex].sets.append(added)
        return []
    }

    /// Rules 7 and 25: every row of the exercise, of any kind, takes the weight and reps; done
    /// flags are unchanged.
    mutating func repeatAll(of exerciseIndex: Int, weight: Weight, reps: Reps) -> [Effect] {
        guard exercises.indices.contains(exerciseIndex) else {
            return []
        }
        for setIndex in exercises[exerciseIndex].sets.indices {
            exercises[exerciseIndex].sets[setIndex].weight = max(weight, .zero)
            exercises[exerciseIndex].sets[setIndex].reps = reps
        }
        return []
    }

    /// Rules 8 and 27: the exercise's ID and name change; its sets, rest, step, RPE and targets stay.
    /// With "Also update program" the slot's new exercise is recorded for F05 (decision #13).
    mutating func swap(_ exerciseIndex: Int, to exerciseID: ExerciseID, name: String, inProgram: Bool) -> [Effect] {
        guard exercises.indices.contains(exerciseIndex) else {
            return []
        }
        exercises[exerciseIndex].exerciseID = exerciseID
        exercises[exerciseIndex].name = name
        if inProgram, let slotID = exercises[exerciseIndex].slotID {
            programUpdates[slotID] = exerciseID
        }
        return []
    }

    /// Rule 9: the rest runs until `timer.endsAt`; the notification is rescheduled for it. The timer
    /// is first held to `WorkoutEngine.longestRest`: `total` into `0 ... longestRest`, and `endsAt` to
    /// at most `longestRest` after `time`, when the rest starts.
    mutating func startRest(_ timer: RestTimer, at time: Date) -> [Effect] {
        let bound = WorkoutEngine.longestRest
        let held = RestTimer(endsAt: min(timer.endsAt, time.adding(bound)), total: min(max(timer.total, .zero), bound))
        rest = held
        return [.scheduleRestNotification(endsAt: held.endsAt)]
    }

    /// Rule 9 and decision #7: "+30s" grows a running rest's `endsAt` and `total`. With no rest
    /// running at `time` (none, or one already over), it starts a fresh rest of `amount` from `time`.
    /// The new total saturates instead of overflowing, then `startRest` clamps it.
    mutating func extendRest(by amount: Duration, at time: Date) -> [Effect] {
        guard let running = rest, running.endsAt > time else {
            return startRest(RestTimer(endsAt: time.adding(amount), total: amount), at: time)
        }
        let total = running.total.saturatingSum(amount)
        return startRest(RestTimer(endsAt: running.endsAt.adding(amount), total: total), at: time)
    }

    /// Rule 9: "Skip" stops the rest.
    mutating func skipRest() -> [Effect] {
        rest = nil
        return [.cancelRestNotification]
    }

    /// Rule 10 (and spec rules 24, 31, 32): the workout ends at `endedAt`, which freezes elapsed
    /// time, and its rest stops. A finished workout is materialised from its final state.
    mutating func end(_ phase: WorkoutPhase, at endedAt: Date) -> [Effect] {
        self.phase = phase
        self.endedAt = endedAt
        rest = nil
        guard phase == .finished else {
            return [.discardLog, .cancelRestNotification]
        }
        return [.materialize(self), .haptic(.workoutFinished), .cancelRestNotification]
    }

    /// Applies `edit` to set `id` of the exercise, when both exist.
    mutating func editSet(_ id: SetID, of exerciseIndex: Int, _ edit: (inout LoggedSet) -> Void) -> [Effect] {
        if let setIndex = row(of: id, in: exerciseIndex) {
            edit(&exercises[exerciseIndex].sets[setIndex])
        }
        return []
    }

    /// The index of set `id` in the exercise's rows, when both exist.
    func row(of id: SetID, in exerciseIndex: Int) -> Int? {
        guard exercises.indices.contains(exerciseIndex) else {
            return nil
        }
        return exercises[exerciseIndex].sets.firstIndex { $0.id == id }
    }
}

private extension Date {
    func adding(_ duration: Duration) -> Date {
        addingTimeInterval(duration / .seconds(1))
    }
}

private extension Duration {
    /// `self + other`, pinned to the largest or smallest `Duration` where the sum would overflow.
    func saturatingSum(_ other: Duration) -> Duration {
        let (sum, overflow) = attoseconds.addingReportingOverflow(other.attoseconds)
        guard overflow else {
            return Duration(attoseconds: sum)
        }
        return Duration(attoseconds: other > .zero ? .max : .min)
    }
}
