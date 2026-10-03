import Foundation
import LedgerDomain
import LedgerPersistence
import Synchronization

/// F05 S3 adversarial round 1: an in-memory history, written from the protocols' doc comments and the notes'
/// decisions, never from the SQL. It is used two ways:
/// - with no fault, as the oracle the GRDB types are compared with over random histories
///   (`HistoryModelAdversarialTests`);
/// - with one `Fault`, as a plausible wrong fake, to see whether the contracts in `LedgerTestSupport` would
///   catch it (`HistoryContractAdversarialTests`).
final class HistoryModel: Sendable {
    /// One plausible mistake of a fake.
    enum Fault: String, CaseIterable, Sendable {
        case tiesInInsertionOrder, datedByEnd, hardDelete, keepsLiveFields, lastIsFirstSet, lastCountsEveryKind
        case lastOfAnyWorkout, bestsCountWarmups, bestsCountDrops, bestSetFewerReps, estimatesAbove12Reps
        case weeksInUTCFromMonday, weeksByTickTime, futureWeeksCount, volumeSkipsWarmups, sessionsNeedADoneSet
        case sessionCountIgnoresDone, recentlyLoggedInWorkoutOrder
        case editDropsRecords, emitsEveryWrite, missesAreMerged, closedRanges, negativeLimitIsAll
        /// Product decision #27: records detected against the all-time bests, the workout's own sets included;
        /// against every other workout's, later ones included; only for the workout written, never again for
        /// the ones after it; and bests "before" a workout that include it.
        case recordsAgainstAllTime, recordsAgainstOtherWorkouts, recordsSkipLaterWorkouts, bestsBeforeIncludeIt
    }

    struct Entry: Sendable {
        var state: WorkoutState
        /// Detected by `redetect`, never given (product decision #27).
        var records: [PersonalRecord] = []
        var isDeleted = false
        var order: Int
    }

    struct State: Sendable {
        var entries: [WorkoutID: Entry] = [:]
        var exerciseOwners: [WorkoutExerciseID: WorkoutID] = [:]
        var setOwners: [SetID: WorkoutID] = [:]
        var programs: [ProgramID: Program] = [:]
        var writes = 0
        var observers: [Observer] = []
    }

    struct Observer: Sendable {
        let limit: Int
        let continuation: AsyncStream<[WorkoutState]>.Continuation
        var last: [WorkoutState]
    }

    let faults: Set<Fault>
    let now: Date
    let state = Mutex(State())

    init(faults: Set<Fault> = [], now: Date = S3Kit.now) {
        self.faults = faults
        self.now = now
    }

    func has(_ fault: Fault) -> Bool {
        faults.contains(fault)
    }

    // MARK: - Reads

    /// When the workout started (product decision #26, S3 fix round 3; round 1 dated by the end, as the slice
    /// did then). The `.datedByEnd` fault dates by the end instead.
    func date(_ workout: WorkoutState) -> Date {
        has(.datedByEnd) ? workout.endedAt ?? workout.startedAt : workout.startedAt
    }

    /// The live workouts with their records, newest first; ties by id text, as the stored id sorts.
    func liveEntries(_ state: State) -> [Entry] {
        state.entries.values.filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                let (left, right) = (date(lhs.state), date(rhs.state))
                if left != right {
                    return left > right
                }
                return has(.tiesInInsertionOrder)
                    ? lhs.order < rhs.order
                    : lhs.state.id.rawValue.uuidString < rhs.state.id.rawValue.uuidString
            }
    }

    func live(_ state: State) -> [WorkoutState] {
        liveEntries(state).map(\.state)
    }

    func contains(_ range: Range<Date>, _ date: Date) -> Bool {
        range.contains(date) || (has(.closedRanges) && date == range.upperBound)
    }

    func recent(_ limit: Int, in state: State) -> [WorkoutState] {
        let all = live(state)
        return limit < 0 && has(.negativeLimitIsAll) ? all : Array(all.prefix(max(0, limit)))
    }

    /// What a history read returns for `workout`: the live-only fields reset.
    func stored(_ workout: WorkoutState) -> WorkoutState {
        guard !has(.keepsLiveFields) else {
            return workout
        }
        var stored = workout
        stored.cursor = nil
        stored.rest = nil
        stored.autoRest = true
        stored.programUpdates = [:]
        for index in stored.exercises.indices {
            stored.exercises[index].lastPerformance = nil
        }
        return stored
    }
}

// MARK: - Writes

extension HistoryModel {
    /// Runs `body` on the state, then tells the observers.
    func write(_ body: (inout State) throws -> Void) throws {
        try state.withLock { state in
            try body(&state)
            state.writes += 1
            for index in state.observers.indices {
                let value = recent(state.observers[index].limit, in: state)
                if value != state.observers[index].last || has(.emitsEveryWrite) {
                    state.observers[index].last = value
                    state.observers[index].continuation.yield(value)
                }
            }
        }
    }

    /// Throws `duplicateIdentifier` as the notes' decision 14 orders it: ids another workout holds (exercises,
    /// then sets, the smallest id first), then an id used twice (exercises, then sets, the first repeat).
    func refuseIDs(of workout: WorkoutState, in state: State) throws {
        let exercises = workout.exercises.map(\.id)
        let sets = workout.exercises.flatMap(\.sets).map(\.id)
        let takenExercises = exercises.filter { state.exerciseOwners[$0].map { $0 != workout.id } ?? false }
        if let taken = takenExercises.map(\.rawValue.uuidString).min() {
            throw LedgerPersistenceError.duplicateIdentifier("workout_exercise \(taken)")
        }
        let takenSets = sets.filter { state.setOwners[$0].map { $0 != workout.id } ?? false }
        if let taken = takenSets.map(\.rawValue.uuidString).min() {
            throw LedgerPersistenceError.duplicateIdentifier("logged_set \(taken)")
        }
        var seenExercises = Set<WorkoutExerciseID>()
        for id in exercises where !seenExercises.insert(id).inserted {
            throw LedgerPersistenceError.duplicateIdentifier("workout_exercise \(id.rawValue.uuidString)")
        }
        var seenSets = Set<SetID>()
        for id in sets where !seenSets.insert(id).inserted {
            throw LedgerPersistenceError.duplicateIdentifier("logged_set \(id.rawValue.uuidString)")
        }
    }

    func refuseNul(in workout: WorkoutState) throws {
        if workout.name.unicodeScalars.contains("\0") {
            throw LedgerPersistenceError.nulInText("workout.name")
        }
        if workout.tag.unicodeScalars.contains("\0") {
            throw LedgerPersistenceError.nulInText("workout.tag")
        }
        if workout.exercises.contains(where: { $0.name.unicodeScalars.contains("\0") }) {
            throw LedgerPersistenceError.nulInText("workout_exercise.name")
        }
    }

    func store(_ workout: WorkoutState, in state: inout State) throws {
        try refuseIDs(of: workout, in: state)
        try refuseNul(in: workout)
        let old = state.entries[workout.id]
        state.entries[workout.id] = Entry(
            state: stored(workout),
            records: old?.records ?? [],
            order: old?.order ?? state.entries.count
        )
        for exercise in workout.exercises {
            state.exerciseOwners[exercise.id] = workout.id
            for set in exercise.sets {
                state.setOwners[set.id] = workout.id
            }
        }
    }

    /// The live workouts in history's order (product decision #26): by date, then id text.
    func historyOrder(_ state: State) -> [Entry] {
        state.entries.values.filter { !$0.isDeleted }.sorted { lhs, rhs in
            (date(lhs.state), lhs.state.id.rawValue.uuidString) < (date(rhs.state), rhs.state.id.rawValue.uuidString)
        }
    }

    /// Product decision #27, written from the protocol's doc rather than the SQL: every live workout's records
    /// are `PersonalRecords.detect` against the bests of the workouts before it, replayed from scratch after
    /// every write (the database replays only what a write touched). `changed` is the workout just written.
    func redetect(after changed: WorkoutID, in state: inout State) {
        let ordered = historyOrder(state)
        let allTime = ordered.reduce(into: PersonalRecords.Bests()) { $0.include($1.state) }
        var before = PersonalRecords.Bests()
        for entry in ordered {
            let id = entry.state.id
            var against = before
            if has(.recordsAgainstAllTime) {
                against = allTime
            }
            if has(.recordsAgainstOtherWorkouts) {
                against = ordered.filter { $0.state.id != id }.reduce(into: .init()) { $0.include($1.state) }
            }
            if !has(.recordsSkipLaterWorkouts) || id == changed {
                state.entries[id]?.records = PersonalRecords.detect(
                    workout: entry.state,
                    against: against,
                    now: entry.state.startedAt
                )
            }
            before.include(entry.state)
        }
    }

    func writeMisses(of slots: [Slot], in state: inout State) {
        for slot in slots {
            for (id, program) in state.programs {
                var edited = program
                for day in edited.days.indices {
                    for index in edited.days[day].slots.indices where edited.days[day].slots[index].id == slot.id {
                        let old = edited.days[day].slots[index].misses
                        edited.days[day].slots[index].misses = has(.missesAreMerged) ? old.union(slot.misses) : slot
                            .misses
                    }
                }
                state.programs[id] = edited
            }
        }
    }
}
