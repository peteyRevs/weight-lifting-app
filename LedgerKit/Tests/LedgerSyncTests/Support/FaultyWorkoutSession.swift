import Foundation
import LedgerDomain
import LedgerTestSupport

/// A `WorkoutSessionClient` that keeps `WorkoutSessionClientContract` except for one `Fault`: what
/// `WorkoutSessionClientContractFaultTests` runs the contract on, to show that each clause can fail. It is a
/// stand-in with switches, built like the fake (an actor over `WorkoutEngine.reduce` with no store), so that it
/// keeps the contract without a fault says little about other implementations: the host is the real second
/// one (S2).
actor FaultyWorkoutSession: WorkoutSessionClient {
    private let fault: Fault?
    private var live: WorkoutState?
    private var ended: WorkoutState?
    private var lastHaptics: [Haptic] = []
    private var listeners: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []

    init(_ fault: Fault?) {
        self.fault = fault
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(
            bufferingPolicy: fault == .keepsOnlyTheNewestUpdate ? .bufferingNewest(1) : .unbounded
        )
        let haptics = fault == .firstElementCarriesHaptics ? lastHaptics : []
        continuation.yield(WorkoutSessionUpdate(state: live, haptics: haptics))
        if fault == .duplicatesTheFirstElement {
            continuation.yield(WorkoutSessionUpdate(state: live, haptics: haptics))
        }
        if fault == .registersAfterASuspension {
            await letOthersIn()
        }
        listeners.append(continuation)
        if fault == .servesOneSubscriber, listeners.count > 1 {
            continuation.finish()
        }
        return stream
    }

    func current() -> WorkoutState? {
        live ?? (fault == .keepsTheEndedWorkoutCurrent ? ended : nil)
    }

    func start(_ initial: WorkoutState) async throws {
        let (snapshot, effects) = try startable(initial)
        if fault == .startsTwiceAtOnce {
            await letOthersIn()
        }
        live = snapshot
        publish(snapshot, WorkoutSessionUpdate.haptics(from: effects) + (fault == .startBuzzes ? [.setLogged] : []))
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await perform(event, through: .apply)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        let finished = try await perform(.finished(endedAt: endedAt), through: .finish)
        guard finished.phase != .live || fault == .returnsFromAnIgnoredEnd else {
            throw WorkoutSessionError.invalidEndDate
        }
        return finished
    }

    func discard(endedAt: Date) async throws {
        let discarded = try await perform(.discarded(endedAt: endedAt), through: .discard)
        guard discarded.phase != .live || fault == .returnsFromAnIgnoredEnd else {
            throw WorkoutSessionError.invalidEndDate
        }
    }
}

/// The call an event came through.
private enum Route { case apply, finish, discard }

/// Starting, applying and ending, with each fault where a host would have it.
private extension FaultyWorkoutSession {
    /// `initial` as the engine starts it, with the engine's effects, when it may start now; else the refusal.
    func startable(_ initial: WorkoutState) throws -> (WorkoutState, [Effect]) {
        if fault == .judgesTheSessionFirst, let live {
            throw WorkoutSessionError.workoutInProgress(live.id)
        }
        let (started, effects) = WorkoutEngine.reduce(nil, Self.envelope(.started(initial), in: initial.id))
        let judgedByPhase = fault == .judgesSnapshotsByPhaseAlone && initial.phase == .live
        guard let snapshot = started ?? (judgedByPhase ? initial : nil) else {
            throw WorkoutSessionError.notStartable(initial.id)
        }
        if let live, fault != .secondStartReplaces {
            throw WorkoutSessionError.workoutInProgress(live.id)
        }
        if let ended, fault == .refusesAStartAfterAnEnd {
            throw WorkoutSessionError.workoutInProgress(ended.id)
        }
        return (snapshot, effects)
    }

    func perform(_ event: WorkoutEvent, through route: Route) async throws -> WorkoutState {
        guard let workout = live else {
            return try await withNothingLive(event)
        }
        if fault == .losesAnEditBetweenCallers {
            await letOthersIn()
        }
        let (reduced, effects) = WorkoutEngine.reduce(workout, Self.envelope(moved(event, route), in: workout.id))
        guard let next = reduced, !effects.isEmpty, !staysLive(next, route) else {
            if fault == .publishesIgnoredEvents {
                publish(workout, [])
            }
            return workout
        }
        let haptics = WorkoutSessionUpdate.haptics(from: effects)
        if next.phase != .live {
            await end(next, haptics)
        } else {
            live = next
            if fault != .skipsUnchangedStates || next != workout {
                publish(next, haptics)
            }
        }
        return fault == .returnsTheStateBefore ? workout : next
    }

    func withNothingLive(_ event: WorkoutEvent) async throws -> WorkoutState {
        guard fault == .startsThroughApply, case let .started(snapshot) = event else {
            throw WorkoutSessionError.noLiveWorkout
        }
        try await start(snapshot)
        return snapshot
    }

    /// The end of the workout: published once, then nothing is live.
    func end(_ next: WorkoutState, _ haptics: [Haptic]) async {
        if fault == .endsTwiceAtOnce {
            await letOthersIn()
        }
        if fault != .discardsSilently || next.phase != .discarded {
            publish(next, haptics)
        }
        if fault == .appliesAfterTheEnd {
            await letOthersIn()
        }
        (live, ended) = (nil, next)
        if fault == .publishesNilAfterTheEnd {
            publish(nil, [])
        }
    }

    /// `terminalThroughApplyStaysLive`: a terminal event that came through `apply` is not taken.
    func staysLive(_ next: WorkoutState, _ route: Route) -> Bool {
        fault == .terminalThroughApplyStaysLive && route == .apply && next.phase != .live
    }

    /// `movesTheEndThroughApply`: a terminal event through `apply`, a second later than it says.
    func moved(_ event: WorkoutEvent, _ route: Route) -> WorkoutEvent {
        guard fault == .movesTheEndThroughApply, route == .apply else {
            return event
        }
        switch event {
        case let .finished(endedAt): return .finished(endedAt: endedAt.addingTimeInterval(1))
        case let .discarded(endedAt): return .discarded(endedAt: endedAt.addingTimeInterval(1))
        default: return event
        }
    }

    func publish(_ state: WorkoutState?, _ haptics: [Haptic]) {
        lastHaptics = fault == .dropsTheHaptics ? [] : haptics
        let update = WorkoutSessionUpdate(state: state, haptics: lastHaptics)
        var someoneStopped = false
        for listener in listeners {
            if case .terminated = listener.yield(update) {
                someoneStopped = true
            }
        }
        if someoneStopped, fault == .cancellationEndsEveryStream {
            listeners.forEach { $0.finish() }
        }
    }

    /// Suspends long enough for every caller already on its way to enter the actor: what an await on a
    /// store or on recovery does to a host.
    func letOthersIn() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }

    /// Any stamp will do: the engine's state and haptics do not depend on it, and nothing here keeps a log.
    static func envelope(_ event: WorkoutEvent, in workout: WorkoutID) -> EventEnvelope {
        EventBuilders.envelope(event, device: EventBuilders.watch, seq: 1, at: EventBuilders.start, workoutID: workout)
    }
}
