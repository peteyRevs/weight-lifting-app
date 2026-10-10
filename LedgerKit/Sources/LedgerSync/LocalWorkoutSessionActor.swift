import Foundation
import LedgerDomain
import os

/// The live workout's host on one device: the real `WorkoutSessionClient` (F10 S2; ADR-004, "The host loop").
/// It stamps each call's event with this device's next `seq` and its hybrid logical clock, reduces it with
/// `WorkoutEngine`, stores it, and only then lets anyone see the result. F17 adds the peer's envelopes and
/// the transport.
///
/// **The rest notification** (F10 S6). The host runs the engine's `.scheduleRestNotification` and
/// `.cancelRestNotification` itself, through the `NotificationsClient` it was given, once the envelope that
/// asked for them is stored: a rest also starts, and a workout also ends, with no screen up. A host that
/// was given no client runs neither, which is the app's case until F23 builds one. Recovery schedules
/// nothing: a notification the system holds outlives the process, and a resumed rest keeps its own.
///
/// **One operation at a time.** An actor is re-entrant at every `await`, and this one awaits its store. So
/// every call that changes the workout, and recovery, is an operation in a queue (`inTurn(_:)`): it starts
/// when the one before it has ended, whatever the callers do. Each runs in a task the actor owns, so a
/// caller that is cancelled (a screen that closes) still gets its event stored, and only waits.
///
/// **Memory follows the store.** State, clock and `seq` change only after the store has taken the envelope,
/// and `live` changes only in the actor turn that publishes the change. So `current()` and a new stream,
/// which do not queue, always agree with the last update. A call whose append the store refuses leaves all
/// of them as they were. A finish or a discard whose end is stored and then cannot be completed has moved the
/// clock and `seq` on, and leaves `live` and the streams as they were (`ending`). When the store throws on
/// an append, the host no longer knows what it holds: the next call reads the store again before it acts
/// (`ready()`).
public actor LocalWorkoutSessionActor: WorkoutSessionClient {
    /// An end that is stored in the log of `live` and not yet complete (`complete(_:)`), with the haptics
    /// its update will carry.
    struct Ending {
        let state: WorkoutState
        let haptics: [Haptic]
    }

    let events: any WorkoutEventStore
    let workouts: any WorkoutRepository
    let programs: any ProgramRepository
    let device: DeviceID
    let notifications: (any NotificationsClient)?
    let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "sync")
    private let now: @Sendable () -> Date

    /// The workout as every reader is told it: what `current()` answers and a new stream starts with.
    var live: WorkoutState?
    /// The highest `seq` stored for `live` from this device.
    var seq: UInt64 = 0
    var clock = HybridLogicalClock()
    /// Set while `live` has ended in its log and the end is not complete: a save or a drop that failed.
    /// Readers still see `live`; every later change to the workout completes the end first (`settle()`).
    var ending: Ending?
    /// Whether a recovery pass has read the store through since the host was built or a write last failed.
    var isRecovered = false
    /// Whether the last recovery pass left an ended log it could not store or drop.
    var hasUnstoredEnds = false
    private var subscribers: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []
    /// Waits for the operation queued last.
    private var queued: @Sendable () async -> Void = {}
    /// True in the task of a running operation: `inTurn` reads it to catch an operation that would queue.
    @TaskLocal private static var isInTurn = false

    /// - Parameters:
    ///   - device: this install's device, which every envelope the host creates names.
    ///   - notifications: what schedules and cancels the rest-over notification; nil runs neither.
    ///   - now: the injected date, read once for each envelope's stamp.
    public init(
        events: any WorkoutEventStore,
        workouts: any WorkoutRepository,
        programs: any ProgramRepository,
        device: DeviceID,
        notifications: (any NotificationsClient)? = nil,
        now: @escaping @Sendable () -> Date
    ) {
        self.notifications = notifications
        self.events = events
        self.workouts = workouts
        self.programs = programs
        self.device = device
        self.now = now
    }

    // MARK: WorkoutSessionClient

    public func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        do {
            try await recovered()
        } catch {
            // A stream cannot throw: it starts with the workout as far as the host knows it, and the
            // recovery that succeeds publishes what it resumes.
            logger.error("A stream opened before recovery succeeded: \(String(describing: error))")
        }
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(WorkoutSessionUpdate(state: live))
        subscribers.append(continuation)
        return stream
    }

    public func current() async throws -> WorkoutState? {
        try await recovered()
        return live
    }

    public func start(_ initial: WorkoutState) async throws {
        try await inTurn { try await self.begin(initial) }
    }

    @discardableResult
    public func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await inTurn { try await self.perform(event) }
    }

    public func finish(endedAt: Date) async throws -> WorkoutState {
        try await inTurn { try await self.end(.finished(endedAt: endedAt), leaving: .finished) }
    }

    public func discard(endedAt: Date) async throws {
        _ = try await inTurn { try await self.end(.discarded(endedAt: endedAt), leaving: .discarded) }
    }

    // MARK: One operation at a time

    /// Runs `operation` once every operation queued before it has ended, in a task of its own, and returns
    /// what it returns or throws.
    ///
    /// - The place in the queue is taken before this suspends, so operations run in the order their calls
    ///   reached the actor, and updates leave in that order.
    /// - An operation waits only for the one before it, and awaits nothing but the stores, so there is no
    ///   cycle to deadlock on and none can be overtaken. No operation may call a method that queues: it
    ///   would wait for an operation queued behind itself, and stop the host for good. A Debug build traps.
    /// - The task is the actor's, not the caller's: cancelling the caller cancels nothing here.
    func inTurn<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        assert(!Self.isInTurn, "An operation of the session host called a method that queues")
        let earlier = queued
        let task = Task {
            await earlier()
            return try await Self.$isInTurn.withValue(true) { try await operation() }
        }
        queued = { _ = await task.result }
        return try await task.value
    }

    /// What `current()` and `updates()` wait for: recovery, queued like any operation when it is due.
    private func recovered() async throws {
        guard !isRecovered else {
            return
        }
        try await inTurn { try await self.ready() }
    }

    // MARK: Publishing

    /// The end of the workout readers were shown, now complete: one last update, and no workout.
    func conclude(_ ended: WorkoutState, haptics: [Haptic]) {
        (live, ending, seq) = (nil, nil, 0)
        publish(ended, haptics)
    }

    /// One update to every stream. A stream whose consumer has stopped (its task was cancelled, or the
    /// stream was dropped) answers a `yield` with `.terminated` and is forgotten here, so ended streams are
    /// held only until the next publication, with no lock and no task.
    func publish(_ state: WorkoutState, _ haptics: [Haptic]) {
        let update = WorkoutSessionUpdate(state: state, haptics: haptics)
        var open: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []
        for subscriber in subscribers {
            if case .terminated = subscriber.yield(update) {
                continue
            }
            open.append(subscriber)
        }
        subscribers = open
    }
}

// MARK: - Own actions (ADR-004, "The host loop")

private extension LocalWorkoutSessionActor {
    /// `start`: the snapshot is judged first, by the engine, then the session. The envelope takes this
    /// device's next `seq` in the store's log of that id: 1, unless the store kept envelopes of this device
    /// under it (a log that replays to nothing is kept). Then the workout is what that whole log replays
    /// to, not the bare snapshot, and the host reads it from the store as recovery does.
    func begin(_ initial: WorkoutState) async throws {
        try await ready()
        let kept = try await events.highestSeq(for: initial.id, device: device)
        var advanced = clock
        let envelope = try stamp(.started(initial), of: initial.id, seq: (kept ?? 0) + 1, with: &advanced)
        let (started, effects) = WorkoutEngine.reduce(nil, envelope)
        guard let started else {
            throw WorkoutSessionError.notStartable(initial.id)
        }
        if let workout = live {
            throw WorkoutSessionError.workoutInProgress(workout.id)
        }
        try await persist(envelope)
        clock = advanced
        guard kept == nil else {
            isRecovered = false
            return try await ready()
        }
        (seq, live) = (envelope.seq, started)
        publish(started, WorkoutSessionUpdate.haptics(from: effects))
        await notify(effects)
    }

    /// An event on the live workout: stamped, reduced, and its effects run in the engine's order.
    /// `.persist` comes first, and a store that refuses it leaves everything as it was. `.materialize` and
    /// `.discardLog` are the end's (`settle()`); the haptics go out with the update; the rest notification
    /// is scheduled or cancelled once the envelope is stored and the update is out (`notify(_:)`), also for
    /// an end that then fails to complete: the workout has ended in its log. `.transmit` and the Live
    /// Activity have no one to run them yet (F17, F21).
    ///
    /// An event the engine ignores has no effects: nothing is stored, and no `seq` or stamp is used.
    func perform(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await ready()
        try await settle()
        guard let workout = live else {
            throw WorkoutSessionError.noLiveWorkout
        }
        var advanced = clock
        let envelope = try stamp(event, of: workout.id, seq: seq + 1, with: &advanced)
        let (reduced, effects) = WorkoutEngine.reduce(workout, envelope)
        guard let next = reduced, !effects.isEmpty else {
            return workout
        }
        // A finish that could never be saved is refused while the workout can still go on.
        if next.phase == .finished, try await events.unreadableCount(for: workout.id) > 0 {
            throw WorkoutSessionError.incompleteLog(workout.id)
        }
        try await persist(envelope)
        (clock, seq) = (advanced, envelope.seq)
        let haptics = WorkoutSessionUpdate.haptics(from: effects)
        guard next.phase == .live else {
            ending = Ending(state: next, haptics: haptics)
            await notify(effects)
            try await settle()
            return next
        }
        live = next
        publish(next, haptics)
        await notify(effects)
        return next
    }

    /// `finish` and `discard`: the terminal event, refused when the engine ignored it. When that end is
    /// already stored and waiting (an earlier call's save or drop failed), this is its retry.
    func end(_ event: WorkoutEvent, leaving phase: WorkoutPhase) async throws -> WorkoutState {
        try await ready()
        if let stored = ending?.state, stored.phase == phase {
            try await settle()
            return stored
        }
        let after = try await perform(event)
        // The outcome is judged, not the date: whatever end the engine ignores is refused here.
        guard after.phase != .live else {
            throw WorkoutSessionError.invalidEndDate
        }
        return after
    }

    /// `event` as this device records it now. `clock` is the caller's copy: it becomes the host's only once
    /// the envelope is stored. The host's own stamp is never the caller's fault, so a stamp that is not
    /// finite is refused here, before the engine could mistake the envelope for a malformed event.
    func stamp(
        _ event: WorkoutEvent,
        of workout: WorkoutID,
        seq: UInt64,
        with clock: inout HybridLogicalClock
    ) throws -> EventEnvelope {
        guard let wallClock = clock.stamp(now: now()) else {
            logger.fault("The session host has no finite stamp for an envelope: its clock is not finite")
            throw LedgerSyncError.noFiniteStamp
        }
        return EventEnvelope(event: event, workoutID: workout, device: device, seq: seq, wallClock: wallClock)
    }

    /// `.persist`: the envelope enters this device's log. When the store throws, what it holds is no longer
    /// known (it may have stored the envelope and failed to say so), so the next call recovers first. The
    /// same when the store answers that it already held the envelope: an own envelope is new, unless memory
    /// is behind the store.
    func persist(_ envelope: EventEnvelope) async throws {
        do {
            guard try await events.append([envelope]) == [envelope] else {
                throw LedgerSyncError.alreadyStored(envelope.key)
            }
        } catch {
            isRecovered = false
            throw error
        }
    }
}
