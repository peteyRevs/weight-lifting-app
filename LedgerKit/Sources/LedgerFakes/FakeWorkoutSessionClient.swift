#if DEBUG
    import Foundation
    import IssueReporting
    import LedgerDomain
    import Synchronization

    /// `WorkoutSessionClient` for previews and tests: the real engine (`WorkoutEngine.reduce`) over a workout
    /// kept in memory, with no store, no recovery and no device effects. It keeps `WorkoutSessionClientContract`
    /// (LedgerTestSupport), as the host must (`LocalWorkoutSessionActor`, F10 S2), so a screen tested on it meets
    /// the same updates in the app.
    ///
    /// It stamps each event as a host would, with `device`, the next `seq` of the workout (from 1) and `now()` as
    /// the wall clock, because the engine reduces envelopes. Nothing a caller can observe depends on the stamp:
    /// an update carries the state and the haptics only, and the fake keeps no log to order. The host's stamps
    /// (a hybrid logical clock, ADR-004) therefore cannot disagree with it.
    public actor FakeWorkoutSessionClient: WorkoutSessionClient {
        /// Every event it was asked for, in call order: `start` as `.started`, `apply`'s event, `finish` as
        /// `.finished` and `discard` as `.discarded`. A call it refused or the engine ignored is listed too.
        public private(set) var applied: [WorkoutEvent] = []

        private let device: DeviceID
        private let now: @Sendable () -> Date
        private var live: WorkoutState?
        private var seq: UInt64 = 0
        private var subscribers: [Int: AsyncStream<WorkoutSessionUpdate>.Continuation] = [:]
        private var nextSubscriber = 0
        /// The subscribers whose streams have ended. A stream's `onTermination` runs synchronously on whatever
        /// thread ends it, and could reach the actor only through an unstructured task (standards §4), so it
        /// notes its id here and the actor drops it on its next call (`dropEnded`).
        private let ended = Mutex<[Int]>([])

        /// - Parameter live: the workout in progress, as if `start` had been called with it; `applied` stays
        ///   empty. A snapshot the engine would not start reports an issue, which fails the test that passed
        ///   it, and leaves no workout.
        public init(
            live: WorkoutState? = nil,
            device: DeviceID = Fixtures.deviceID,
            now: @escaping @Sendable () -> Date = { Fixtures.now }
        ) {
            self.device = device
            self.now = now
            guard let live else {
                return
            }
            let envelope = EventEnvelope(
                event: .started(live),
                workoutID: live.id,
                device: device,
                seq: 1,
                wallClock: now()
            )
            let started = WorkoutEngine.reduce(nil, envelope).0
            if started == nil {
                reportIssue("FakeWorkoutSessionClient: `live` is not a snapshot the engine starts (\(live.phase))")
            }
            self.live = started
            seq = 1
        }

        /// How many streams it still holds, for the tests that show it forgets them. A stream ends when its
        /// consumer's task is cancelled or the stream is dropped, and is forgotten at the next subscription
        /// or publication.
        var subscriberCount: Int {
            subscribers.count
        }

        public func updates() -> AsyncStream<WorkoutSessionUpdate> {
            dropEnded()
            let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
            let id = nextSubscriber
            nextSubscriber += 1
            continuation.yield(WorkoutSessionUpdate(state: live))
            continuation.onTermination = { [weak self] _ in
                self?.ended.withLock { $0.append(id) }
            }
            subscribers[id] = continuation
            return stream
        }

        public func current() -> WorkoutState? {
            live
        }

        public func start(_ initial: WorkoutState) throws {
            applied.append(.started(initial))
            let (started, effects) = WorkoutEngine.reduce(nil, envelope(.started(initial), in: initial.id, seq: 1))
            guard let started else {
                throw WorkoutSessionError.notStartable(initial.id)
            }
            if let workout = live {
                throw WorkoutSessionError.workoutInProgress(workout.id)
            }
            live = started
            seq = 1
            publish(started, effects)
        }

        @discardableResult
        public func apply(_ event: WorkoutEvent) throws -> WorkoutState {
            applied.append(event)
            guard let workout = live else {
                throw WorkoutSessionError.noLiveWorkout
            }
            let (reduced, effects) = WorkoutEngine.reduce(workout, envelope(event, in: workout.id, seq: seq + 1))
            // ADR-004: an envelope the engine ignores changes nothing and has no effects, `.persist` included,
            // so it never enters the log. It takes no `seq` and is not published.
            guard let next = reduced, !effects.isEmpty else {
                return workout
            }
            seq += 1
            live = next.phase == .live ? next : nil
            publish(next, effects)
            return next
        }

        public func finish(endedAt: Date) throws -> WorkoutState {
            try apply(.finished(endedAt: endedAt))
        }

        public func discard(endedAt: Date) throws {
            try apply(.discarded(endedAt: endedAt))
        }

        private func envelope(_ event: WorkoutEvent, in workout: WorkoutID, seq: UInt64) -> EventEnvelope {
            EventEnvelope(event: event, workoutID: workout, device: device, seq: seq, wallClock: now())
        }

        /// One update to every stream that has not ended: the state, and the engine's effects by the one
        /// forwarding rule.
        private func publish(_ state: WorkoutState, _ effects: [Effect]) {
            dropEnded()
            let update = WorkoutSessionUpdate(state: state, effects: WorkoutSessionUpdate.feedback(from: effects))
            for continuation in subscribers.values {
                continuation.yield(update)
            }
        }

        /// Forgets the subscribers whose streams have ended. Every subscription and every publication starts
        /// with it, so the fake holds at most the streams that ended since the last of those: a screen that
        /// comes and goes for hours while no workout starts leaves one continuation behind, not thousands.
        private func dropEnded() {
            let ids = ended.withLock { ids in
                defer { ids.removeAll() }
                return ids
            }
            for id in ids {
                subscribers[id] = nil
            }
        }
    }
#endif
