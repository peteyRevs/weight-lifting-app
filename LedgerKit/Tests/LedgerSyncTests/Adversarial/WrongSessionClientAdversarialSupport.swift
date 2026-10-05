import Foundation
import LedgerDomain
import LedgerTestSupport

/// A `WorkoutSessionClient` written from the protocol's documentation alone (over `WorkoutEngine.reduce`,
/// with no store), with at most one deliberate fault: the contract must accept it without a fault and
/// reject it with any. It never looks at `FakeWorkoutSessionClient` or the implementer's faulty client.
actor WrongSessionClient: WorkoutSessionClient {
    typealias Update = WorkoutSessionUpdate

    private let fault: SeamFault?
    private var live: WorkoutState?
    /// The workout before the last change, and the last one that ended.
    private var before: WorkoutState?
    private var ended: WorkoutState?
    /// An ended workout `current()` still answers with (the three `…LeavesCurrent` faults).
    private var leftCurrent: WorkoutState?
    private var lastEffects: [Haptic] = []
    private var listeners: [AsyncStream<Update>.Continuation] = []
    /// A set edit kept back from the second subscriber (`swapsForSecondSubscriber`).
    private var held: Update?
    /// Updates committed and not yet published (`SeamFault.batching`).
    private var pending: [Update] = []
    private let stopped = SeamCounter()

    init(_ fault: SeamFault? = nil) {
        self.fault = fault
    }

    func updates() async -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Update.self,
            bufferingPolicy: fault == .newestOnly ? .bufferingNewest(1) : .unbounded
        )
        continuation.onTermination = { [stopped] _ in _ = stopped.next() }
        switch fault {
        case .noFirstElement: break
        case .firstElementRepeatsEffects: continuation.yield(Update(state: live, haptics: lastEffects))
        case .firstElementIsStale: continuation.yield(Update(state: live == nil ? nil : before))
        case .endedShownToNewStreams: continuation.yield(Update(state: live ?? ended))
        default: continuation.yield(Update(state: live))
        }
        if fault == .racyLateRegistration {
            await letOthersIn()
        }
        listeners.append(continuation)
        if fault == .onlyFirstSubscriber, listeners.count > 1 {
            continuation.finish()
        }
        return stream
    }

    func current() -> WorkoutState? {
        fault == .currentLags ? before : live ?? leftCurrent
    }

    func start(_ initial: WorkoutState) async throws {
        let (started, effects) = Seam.engine(nil, .started(initial), in: initial.id)
        if fault == .inProgressBeforeNotStartable, let live {
            throw WorkoutSessionError.workoutInProgress(live.id)
        }
        guard started != nil || looksStartable(initial) else {
            if fault == .unstartableStartIsSilent {
                return
            }
            throw WorkoutSessionError.notStartable(initial.id)
        }
        if let live, fault != .secondStartReplaces {
            throw WorkoutSessionError.workoutInProgress(fault == .inProgressNamesTheNewWorkout ? initial.id : live.id)
        }
        if let ended, fault == .restartRefused {
            throw WorkoutSessionError.workoutInProgress(ended.id)
        }
        if fault == .racyDoubleStart {
            await letOthersIn()
        }
        (before, live, leftCurrent) = (live, initial, nil)
        if fault == .startUnpublished {
            listeners.forEach { $0.finish() }
        } else {
            publish(Update(state: initial, haptics: forwarded(effects)))
        }
    }

    /// `judgesSnapshotsByPhaseAndStart`: a snapshot passes on its phase and start date alone.
    private func looksStartable(_ initial: WorkoutState) -> Bool {
        fault == .judgesSnapshotsByPhaseAndStart && initial.phase == .live
            && initial.startedAt.timeIntervalSinceReferenceDate.isFinite
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await perform(event, .apply)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await perform(.finished(endedAt: endedAt), .finish)
    }

    func discard(endedAt: Date) async throws {
        if live == nil, fault == .discardSilentWhenIdle {
            return
        }
        _ = try await perform(.discarded(endedAt: endedAt), .discard)
    }

    private func perform(_ event: WorkoutEvent, _ route: SeamRoute) async throws -> WorkoutState {
        guard let current = live else {
            return try await idle(event)
        }
        if fault == .racyLostUpdate {
            await letOthersIn()
        }
        let (reduced, effects) = Seam.engine(current, moved(event, route), in: current.id)
        guard let next = reduced, !effects.isEmpty else {
            return try ignored(current, route)
        }
        let update = Update(state: next, haptics: forwarded(effects))
        if next.phase != .live, fault == .racyDoubleEnd || fault == .racyApplyAfterEnd {
            return await endedAcrossASuspension(update, next)
        }
        commit(next, route)
        if let fault, SeamFault.batching.contains(fault) {
            return await publishedTogether(update, next)
        }
        if publishes(next, after: current, route) {
            publish(update, holdable: event.isSetEdit)
        }
        afterEnd(next)
        return fault == .returnsStateBefore ? current : next
    }

    private func commit(_ next: WorkoutState, _ route: SeamRoute) {
        before = live
        live = next.phase == .live ? next : nil
        guard live == nil else {
            return
        }
        ended = next
        switch (fault, route) {
        case (.finishLeavesCurrent, .finish), (.discardLeavesCurrent, .discard), (.terminalApplyLeavesCurrent, .apply):
            leftCurrent = next
        default:
            break
        }
    }

    /// A call with nothing live.
    private func idle(_ event: WorkoutEvent) async throws -> WorkoutState {
        if fault == .applyStartsWhenIdle, case let .started(snapshot) = event {
            try await start(snapshot)
            return snapshot
        }
        throw WorkoutSessionError.noLiveWorkout
    }

    /// An event the engine ignores: the workout as it stands, and nothing published. Through `finish` and
    /// `discard` it is refused with `invalidEndDate` (criterion 4, as revised after round 1).
    private func ignored(_ current: WorkoutState, _ route: SeamRoute) throws -> WorkoutState {
        if fault == .publishesIgnored {
            publish(Update(state: current))
        }
        if fault == .nonFiniteEndEnds, route != .apply {
            live = nil
        }
        if fault != .nonFiniteEndReturns, route != .apply {
            throw WorkoutSessionError.invalidEndDate
        }
        return current
    }
}

/// What a faulty client publishes, and to whom.
private extension WrongSessionClient {
    func publishes(_ next: WorkoutState, after current: WorkoutState, _ route: SeamRoute) -> Bool {
        switch fault {
        case .skipsUnchanged: next != current
        case .finishUnpublished: route != .finish
        case .discardUnpublished: route != .discard
        default: true
        }
    }

    func afterEnd(_ next: WorkoutState) {
        guard next.phase != .live else {
            return
        }
        if fault == .endPublishesNil {
            publish(Update(state: nil))
        }
        if fault == .endsStreamsWithTheWorkout {
            listeners.forEach { $0.finish() }
        }
    }

    func forwarded(_ effects: [Effect]) -> [Haptic] {
        switch fault {
        case .dropsHaptics: []
        default: Seam.haptics(effects)
        }
    }

    func publish(_ update: Update, holdable: Bool = false) {
        lastEffects = update.haptics
        if fault == .cancelEndsEveryone, stopped.value > 0 {
            listeners.forEach { $0.finish() }
        }
        for (index, listener) in listeners.enumerated() where fault != .onlyFirstSubscriber || index == 0 {
            if fault == .swapsForSecondSubscriber, index == 1 {
                swap(update, holdable: holdable, to: listener)
                continue
            }
            listener.yield(update)
            if fault == .duplicatesUpdates {
                listener.yield(update)
            }
        }
    }

    /// Keeps a set edit back until the next update has gone out, then sends it.
    func swap(_ update: Update, holdable: Bool, to listener: AsyncStream<Update>.Continuation) {
        if holdable, held == nil {
            held = update
            return
        }
        listener.yield(update)
        if let kept = held {
            listener.yield(kept)
            held = nil
        }
    }
}

/// The call an event came through.
private enum SeamRoute { case apply, finish, discard }

/// The faults that need two calls inside the client at once.
private extension WrongSessionClient {
    /// Suspends long enough for every caller already on its way to enter the actor.
    func letOthersIn() async {
        for _ in 0 ..< 200 {
            await Task.yield()
        }
    }

    /// `terminalApplyMovesTheEnd`: a terminal event through `apply`, a second later than it says.
    func moved(_ event: WorkoutEvent, _ route: SeamRoute) -> WorkoutEvent {
        guard fault == .terminalApplyMovesTheEnd, route == .apply else {
            return event
        }
        switch event {
        case let .finished(endedAt): return .finished(endedAt: endedAt.addingTimeInterval(1))
        case let .discarded(endedAt): return .discarded(endedAt: endedAt.addingTimeInterval(1))
        default: return event
        }
    }

    /// An end with a suspension inside it. `racyDoubleEnd` suspends before it commits, so every end that
    /// overlaps it ends the workout too; `racyApplyAfterEnd` publishes the end, then suspends before it
    /// lets go of the workout, so an overlapping apply lands after the end.
    func endedAcrossASuspension(_ update: Update, _ next: WorkoutState) async -> WorkoutState {
        if fault == .racyApplyAfterEnd {
            publish(update)
        }
        await letOthersIn()
        (before, live, ended) = (live, nil, next)
        if fault == .racyDoubleEnd {
            publish(update)
        }
        return next
    }

    /// Publishes this update with those of the applies that overlapped it, in the fault's order.
    func publishedTogether(_ update: Update, _ next: WorkoutState) async -> WorkoutState {
        pending.append(update)
        await letOthersIn()
        var batch = pending
        pending = []
        switch fault {
        case .racyReversed: batch.reverse()
        case .racyScrambled where batch.count > 2: batch.swapAt(0, 1)
        case .racyDropsOne where batch.count > 1: batch.removeFirst()
        default: break
        }
        for (index, listener) in listeners.enumerated() {
            var mine = batch
            if fault == .racySecondSubscriberScrambled, index == 1, mine.count > 2 {
                mine.swapAt(0, 1)
            }
            mine.forEach { listener.yield($0) }
        }
        return fault == .racyReturnsLatest ? live ?? next : next
    }
}
