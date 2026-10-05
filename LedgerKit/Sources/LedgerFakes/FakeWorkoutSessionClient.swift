#if DEBUG
    import Foundation
    import IssueReporting
    import LedgerDomain

    /// `WorkoutSessionClient` for previews and tests: the real engine (`WorkoutEngine.reduce`) over a workout
    /// kept in memory, with no store, no recovery and no device effects. It keeps `WorkoutSessionClientContract`
    /// (LedgerTestSupport), as the host must (`LocalWorkoutSessionActor`, F10 S2), so a screen tested on it meets
    /// the same updates in the app.
    ///
    /// The engine reduces envelopes, so the fake stamps each event: `Fixtures.deviceID`, the next `seq` of the
    /// workout (from 1) and `Fixtures.now` as the wall clock. Nothing a caller can observe depends on the stamp:
    /// an update carries the state and the haptics only, and the fake keeps no log to order. The host's stamps
    /// (a hybrid logical clock, ADR-004) therefore cannot disagree with it.
    public actor FakeWorkoutSessionClient: WorkoutSessionClient {
        /// Every event it was asked for, in call order: `start` as `.started`, `apply`'s event, `finish` as
        /// `.finished` and `discard` as `.discarded`. A call it refused or the engine ignored is listed too.
        public private(set) var applied: [WorkoutEvent] = []

        private var live: WorkoutState?
        private var seq: UInt64 = 0
        private var subscribers: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []

        /// - Parameter live: the workout in progress, as if `start` had been called with it; `applied` stays
        ///   empty. A snapshot the engine would not start reports an issue, which fails the test that passed
        ///   it, and leaves no workout.
        public init(live: WorkoutState? = nil) {
            guard let live else {
                return
            }
            let started = WorkoutEngine.reduce(nil, Self.envelope(.started(live), in: live.id, seq: 1)).0
            if started == nil {
                reportIssue("FakeWorkoutSessionClient: `live` is not a snapshot the engine starts (\(live.phase))")
            }
            self.live = started
            seq = 1
        }

        public func updates() -> AsyncStream<WorkoutSessionUpdate> {
            let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
            continuation.yield(WorkoutSessionUpdate(state: live))
            subscribers.append(continuation)
            return stream
        }

        public func current() -> WorkoutState? {
            live
        }

        public func start(_ initial: WorkoutState) throws {
            applied.append(.started(initial))
            let (started, effects) = WorkoutEngine.reduce(nil, Self.envelope(.started(initial), in: initial.id, seq: 1))
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
            let (reduced, effects) = WorkoutEngine.reduce(workout, Self.envelope(event, in: workout.id, seq: seq + 1))
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
            let finished = try apply(.finished(endedAt: endedAt))
            // The outcome is judged, not the date: whatever end the engine ignores is refused here.
            guard finished.phase != .live else {
                throw WorkoutSessionError.invalidEndDate
            }
            return finished
        }

        public func discard(endedAt: Date) throws {
            guard try apply(.discarded(endedAt: endedAt)).phase != .live else {
                throw WorkoutSessionError.invalidEndDate
            }
        }

        private static func envelope(_ event: WorkoutEvent, in workout: WorkoutID, seq: UInt64) -> EventEnvelope {
            EventEnvelope(
                event: event,
                workoutID: workout,
                device: Fixtures.deviceID,
                seq: seq,
                wallClock: Fixtures.now
            )
        }

        /// One update to every stream: the state, and the engine's haptics by the one forwarding rule. A
        /// stream whose consumer has stopped (its task was cancelled, or the stream was dropped) answers a
        /// `yield` with `.terminated` and is forgotten here, so ended streams are held only until the next
        /// publication, with no lock and no task of the fake's own.
        private func publish(_ state: WorkoutState, _ effects: [Effect]) {
            let update = WorkoutSessionUpdate(state: state, haptics: WorkoutSessionUpdate.haptics(from: effects))
            subscribers.removeAll { subscriber in
                if case .terminated = subscriber.yield(update) {
                    true
                } else {
                    false
                }
            }
        }
    }
#endif
