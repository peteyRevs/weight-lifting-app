import Foundation
import LedgerDomain
import LedgerTestSupport

/// A `WorkoutSessionClient` that keeps `WorkoutSessionClientContract` except for one `Fault`: what
/// `WorkoutSessionClientContractFaultTests` runs the contract on, to show that each clause can fail. It is
/// written from the protocol's documentation, not copied from `FakeWorkoutSessionClient`, so with no fault it
/// is also a second implementation the clauses accept.
actor FaultyWorkoutSession: WorkoutSessionClient {
    /// One way a host could plausibly get the seam wrong.
    enum Fault: String, CaseIterable, Sendable, CustomStringConvertible {
        /// A new stream's first element repeats the last update's effects.
        case firstElementCarriesEffects
        /// An update carries every effect of the engine, not `feedback(from:)` of them.
        case forwardsEveryEffect
        /// An event the engine ignores is published as one more, unchanged update.
        case publishesIgnoredEvents
        /// An accepted event that leaves the state as it was is not published.
        case skipsUnchangedStates
        /// `apply` returns the state before the event.
        case returnsTheStateBefore
        /// After a finish, `current()` still answers with the finished workout.
        case keepsTheEndedWorkoutCurrent
        /// After the update that ends a workout comes one more, with a nil state.
        case publishesNilAfterTheEnd
        /// The live workout is checked before the snapshot, so `workoutInProgress` hides `notStartable`.
        case judgesTheSessionFirst
        /// `apply(.started)` with nothing live starts a workout.
        case startsThroughApply
        /// A stream keeps only its newest update, as the repositories' observations do.
        case keepsOnlyTheNewestUpdate
        /// A discard ends the workout without an update.
        case discardsSilently

        var description: String {
            rawValue
        }

        /// How the name of a clause this fault must break begins.
        var brokenClause: String {
            switch self {
            case .firstElementCarriesEffects: "a stream opened on a live workout starts with it"
            case .forwardsEveryEffect, .returnsTheStateBefore: "apply returns the state after the event"
            case .publishesIgnoredEvents: "an event the engine ignores"
            case .skipsUnchangedStates: "an event the engine accepts is published once"
            case .keepsTheEndedWorkoutCurrent, .publishesNilAfterTheEnd: "finish returns the finished state"
            case .judgesTheSessionFirst: "a snapshot the engine would not start"
            case .startsThroughApply: "apply, finish and discard with nothing live"
            case .keepsOnlyTheNewestUpdate: "updates under rapid apply calls"
            case .discardsSilently: "discard publishes the discarded state once"
            }
        }
    }

    private let fault: Fault?
    private var live: WorkoutState?
    private var ended: WorkoutState?
    private var lastEffects: [Effect] = []
    private var continuations: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []

    init(_ fault: Fault?) {
        self.fault = fault
    }

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(
            bufferingPolicy: fault == .keepsOnlyTheNewestUpdate ? .bufferingNewest(1) : .unbounded
        )
        let effects = fault == .firstElementCarriesEffects ? lastEffects : []
        continuation.yield(WorkoutSessionUpdate(state: live, effects: effects))
        continuations.append(continuation)
        return stream
    }

    func current() -> WorkoutState? {
        live ?? (fault == .keepsTheEndedWorkoutCurrent ? ended : nil)
    }

    func start(_ initial: WorkoutState) throws {
        if fault == .judgesTheSessionFirst, let live {
            throw WorkoutSessionError.workoutInProgress(live.id)
        }
        let (started, effects) = WorkoutEngine.reduce(nil, Self.envelope(.started(initial), in: initial.id))
        guard let started else {
            throw WorkoutSessionError.notStartable(initial.id)
        }
        if let live {
            throw WorkoutSessionError.workoutInProgress(live.id)
        }
        live = started
        publish(started, effects)
    }

    func apply(_ event: WorkoutEvent) throws -> WorkoutState {
        guard let workout = live else {
            return try applyWithNothingLive(event)
        }
        let (reduced, effects) = WorkoutEngine.reduce(workout, Self.envelope(event, in: workout.id))
        guard let next = reduced, !effects.isEmpty else {
            if fault == .publishesIgnoredEvents {
                publish(workout, [])
            }
            return workout
        }
        live = next.phase == .live ? next : nil
        ended = live == nil ? next : nil
        if !isSilent(next, after: workout) {
            publish(next, effects)
        }
        if fault == .publishesNilAfterTheEnd, live == nil {
            publish(nil, [])
        }
        return fault == .returnsTheStateBefore ? workout : next
    }

    func finish(endedAt: Date) throws -> WorkoutState {
        try apply(.finished(endedAt: endedAt))
    }

    func discard(endedAt: Date) throws {
        _ = try apply(.discarded(endedAt: endedAt))
    }

    private func applyWithNothingLive(_ event: WorkoutEvent) throws -> WorkoutState {
        guard fault == .startsThroughApply, case let .started(snapshot) = event else {
            throw WorkoutSessionError.noLiveWorkout
        }
        try start(snapshot)
        return snapshot
    }

    /// Whether a fault keeps the change from `before` to `next` out of the streams.
    private func isSilent(_ next: WorkoutState, after before: WorkoutState) -> Bool {
        switch fault {
        case .skipsUnchangedStates: next == before
        case .discardsSilently: next.phase == .discarded
        default: false
        }
    }

    private func publish(_ state: WorkoutState?, _ effects: [Effect]) {
        lastEffects = fault == .forwardsEveryEffect ? effects : WorkoutSessionUpdate.feedback(from: effects)
        for continuation in continuations {
            continuation.yield(WorkoutSessionUpdate(state: state, effects: lastEffects))
        }
    }

    /// Any stamp will do: the engine's state and haptics do not depend on it, and nothing here keeps a log.
    private static func envelope(_ event: WorkoutEvent, in workout: WorkoutID) -> EventEnvelope {
        EventBuilders.envelope(event, device: EventBuilders.watch, seq: 1, at: EventBuilders.start, workoutID: workout)
    }
}
