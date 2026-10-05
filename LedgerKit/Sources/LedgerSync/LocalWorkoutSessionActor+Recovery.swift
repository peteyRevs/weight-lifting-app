import Foundation
import LedgerDomain

/// Recovery (ADR-004 rule 6 and "Recovery on launch"; F10 S2 criterion 6): bringing the host's memory in line
/// with its store, and finishing what the store shows unfinished. The same pass serves a launch, a return
/// to the foreground after a failure, and the call that follows a failed write.
public extension LocalWorkoutSessionActor {
    /// The launch step. For each log the store has not compacted, by what it replays to:
    /// - live: the workout is resumed, with no haptic and no effect run (of two, the one that started last);
    /// - finished: it is saved to history, with its misses and its program changes, and its log dropped with
    ///   it (`complete(_:)`);
    /// - discarded: its log is dropped;
    /// - nothing: the log is kept, as is an ended log with rows this version cannot read.
    ///
    /// Every log is read before any ended one is completed, and the ended ones are completed in the order
    /// their workouts started, then by id, whatever order the store lists them in: of two finished workouts
    /// the later one's misses and program changes are written last.
    ///
    /// The clock continues from the store's newest stamp. Running it again changes nothing. It is queued
    /// like every operation, and the first protocol call runs it when the launch has not.
    ///
    /// Returns the live workout. Throws what kept it from reading the store, or else, once every log has
    /// been dealt with, the first error that kept an ended workout from being saved or dropped: that log
    /// is kept, and `needsRecovery` stays true until a later pass succeeds.
    @discardableResult
    func resumeFromStore() async throws -> WorkoutState? {
        try await inTurn { try await self.recover() }
    }

    /// Whether `resumeFromStore()` has work to do: no pass has read the store through, or an ended workout
    /// is not yet saved or dropped. The launch runs the step again on a return to the foreground while this
    /// is true.
    var needsRecovery: Bool {
        !isRecovered || ending != nil || hasUnstoredEnds
    }
}

extension LocalWorkoutSessionActor {
    private func recover() async throws -> WorkoutState? {
        if let failure = try await reconcile().first {
            throw failure
        }
        return live
    }

    /// In an operation's turn, before it acts: recovery, when no pass has read the store through since the
    /// host was built or a write last failed. An ended log it cannot store does not stop the call: the
    /// session itself is known, the failure is logged, and the launch retries it.
    func ready() async throws {
        guard !isRecovered else {
            return
        }
        _ = try await reconcile()
    }

    /// One pass over the store. Throws when the store cannot be read, and then knows no more than before;
    /// otherwise returns what kept each ended workout from being stored or dropped.
    private func reconcile() async throws -> [any Error] {
        if let newest = try await events.newestWallClock() {
            clock.observe(newest)
        }
        var resumable: [WorkoutState] = []
        var ended: [WorkoutState] = []
        for workout in try await events.uncompactedWorkoutIDs() {
            guard let state = try await WorkoutEngine.replay(events.envelopes(for: workout)) else {
                logger.notice("Log \(workout.rawValue, privacy: .public) replays to no workout; kept")
                continue
            }
            if state.phase == .live {
                resumable.append(state)
            } else if state.id == live?.id {
                // The workout readers still see has ended in its log: that end is completed below.
                ending = ending ?? Ending(state: state, haptics: [])
            } else {
                ended.append(state)
            }
        }
        if let ending {
            ended.append(ending.state)
        }
        // In history's order, not the store's: a later workout's misses and program changes land last.
        var failures: [any Error] = []
        for state in ended.sorted(by: Self.startedBefore) {
            if let failure = await recoverEnded(state) {
                failures.append(failure)
            }
        }
        try await resume(resumable)
        isRecovered = true
        hasUnstoredEnds = !failures.isEmpty
        return failures
    }

    /// Makes the live log the workout, with this device's highest stored `seq`, and tells any stream that
    /// was told otherwise. `start` refuses a second live workout, so only a peer can bring two (F17, whose
    /// rule it will be): until then the one that started last is resumed and the other kept.
    private func resume(_ resumable: [WorkoutState]) async throws {
        guard let resumed = resumable.max(by: Self.startedBefore) else {
            if let shown = live, ending == nil {
                // Only damage does this (the log's `started` cannot be read, or the log is gone).
                logger.fault("No stored log replays to \(shown.id.rawValue, privacy: .public), which the host shows")
            }
            return
        }
        if resumable.count > 1 {
            logger.fault("\(resumable.count) live logs; resumed \(resumed.id.rawValue, privacy: .public)")
        }
        let stored = try await events.highestSeq(for: resumed.id, device: device) ?? 0
        seq = stored
        if resumed != live {
            live = resumed
            publish(resumed, [])
        }
    }

    /// History's order of two workouts: by start, then by id (product decision #26).
    private static func startedBefore(_ one: WorkoutState, _ other: WorkoutState) -> Bool {
        (one.startedAt, one.id.rawValue.uuidString) < (other.startedAt, other.id.rawValue.uuidString)
    }

    /// An ended workout met by recovery: completes it, or returns why it could not. When it is the workout
    /// readers still see as live (its end failed earlier in this process), they are told now, without a
    /// haptic: nothing was just logged.
    private func recoverEnded(_ ended: WorkoutState) async -> (any Error)? {
        do {
            try await complete(ended)
            if ended.id == live?.id {
                conclude(ended, haptics: [])
            }
            return nil
        } catch WorkoutSessionError.incompleteLog {
            logger.notice("Log \(ended.id.rawValue, privacy: .public) is finished but incomplete; kept")
            return nil
        } catch {
            logger.fault("Log \(ended.id.rawValue, privacy: .public) kept: \(String(describing: error))")
            return error
        }
    }

    /// Completes the end that is stored for the workout readers still see, if there is one: the retry of a
    /// save or a drop that failed. Only then is the end published.
    func settle() async throws {
        guard let ending else {
            return
        }
        try await complete(ending.state)
        conclude(ending.state, haptics: ending.haptics)
    }

    /// What an ended log still needs. A finished workout is saved to history, an idempotent upsert, with its
    /// misses and its program changes, and its log is dropped in the same transaction
    /// (`WorkoutRepository.materialize(_:slotUpdates:droppingLog:)`): over a database the workout is in
    /// history and its log gone, or neither. A throw leaves the log for the next attempt.
    ///
    /// **An end is complete when its log is gone from this host's event store**, and the host does not take
    /// the repository's word for that. A repository that holds no log answers `false`, and one that does
    /// answers for its own database, which need not be the one behind the event store the host was given. So
    /// after a save that answered `true` the host looks in its event store (`holdsNoLog(of:)`), and it drops
    /// the log there itself, in a second step, whenever the answer was `false`, the log is still listed, or
    /// the look failed. That second step is the one that drops a discarded workout's log.
    ///
    /// The host never materialises or compacts a log that holds rows this version cannot read
    /// (`WorkoutEventStore.unreadableCount(for:)`): a finished one throws `incompleteLog`, and a discarded
    /// one, which is over all the same, keeps its log for a version that can.
    func complete(_ ended: WorkoutState) async throws {
        guard try await events.unreadableCount(for: ended.id) == 0 else {
            guard ended.phase == .discarded else {
                throw WorkoutSessionError.incompleteLog(ended.id)
            }
            logger.notice("Log \(ended.id.rawValue, privacy: .public) is discarded but incomplete; kept")
            return
        }
        if ended.phase == .finished {
            let slots = try await slotUpdates(for: ended)
            let isDropped = try await workouts.materialize(ended, slotUpdates: slots, droppingLog: true)
            if isDropped, await holdsNoLog(of: ended.id) {
                return
            }
        }
        try await events.compact(workout: ended.id)
    }

    /// Whether this host's event store lists no log of `workout`: one read, of the logs the store holds,
    /// after a save that answered that the log went with it.
    ///
    /// A log that is still listed means the repository dropped another store's: the two are not one
    /// database. The app never pairs them so, hence the fault in the log. A read that fails is answered
    /// `false` too, and is not thrown: the workout is saved by then, and the caller's compaction, which does
    /// nothing to a log that is gone, settles what the read could not.
    private func holdsNoLog(of workout: WorkoutID) async -> Bool {
        do {
            guard try await events.uncompactedWorkoutIDs().contains(workout) else {
                return true
            }
            logger.fault("Log \(workout.rawValue, privacy: .public) outlived its save: the stores are not one database")
        } catch {
            let reason = String(describing: error)
            logger.error("Log \(workout.rawValue, privacy: .public) not checked after its save: \(reason)")
        }
        return false
    }

    /// Rule 13: the misses the workout leaves on its program's slots (`MissTracking`), on the program as it is
    /// stored now, so that misses recorded since the workout started are kept. None for an ad-hoc workout, or
    /// when the active program is not the workout's.
    private func slotUpdates(for workout: WorkoutState) async throws -> [Slot] {
        guard let source = workout.source,
              let program = try await programs.active(),
              program.id == source.programID
        else {
            return []
        }
        let slots = program.days.flatMap(\.slots)
        return workout.exercises.compactMap { exercise in
            slots.first { $0.id == exercise.slotID }.map { slot in
                MissTracking.update(
                    slot: slot,
                    exercise: exercise,
                    weekIndex: source.weekIndex,
                    isDeload: workout.isDeload
                )
            }
        }
    }
}
