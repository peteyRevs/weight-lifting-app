import Foundation
import LedgerDomain
import LedgerTestSupport

/// Round 2's ways for a `WorkoutSessionClient` to be wrong, written after the fix round and unlike any of
/// round 1's `SeamFault`s: the edges of the `invalidEndDate` rule (criterion 4, as revised), the two snapshots
/// the contract added, and new shapes of fault that show only when calls overlap.
enum SeamLateFault: String, Sendable, CaseIterable, CustomStringConvertible {
    // The invalidEndDate rule, on calls made one after another.
    case invalidEndIsNoLiveWorkout = "throws noLiveWorkout for a finish or discard the engine ignores"
    case invalidEndThroughApplyThrows = "throws invalidEndDate for an ignored end through apply as well"
    case invalidEndWhenIdle = "judges the date first: with nothing live, such a finish or discard throws invalidEndDate"
    case invalidDiscardReturns = "throws invalidEndDate for a finish only: such a discard returns"
    case invalidEndPublishes = "publishes the unchanged workout when it throws invalidEndDate"
    case invalidEndSticks = "refuses every later end with invalidEndDate once it has refused one"
    // The two unstartable snapshots the contract added: a judge that checks everything but one kind.
    case judgesAllButRestLength = "starts a snapshot whose only fault is a rest longer than an hour"
    case judgesAllButSetDates = "starts a snapshot whose only fault is a set done at a date that is not finite"
    // Only when calls overlap.
    case startPublishesLate = "commits a start, suspends, then publishes it: an overlapping apply is published first"
    case startCommitsLate = "publishes a start, suspends, then commits it: the update is ahead of current()"
    case losingEndRepublishes = "republishes the ending when an end loses to one still inside the client"
    case registersBeforeItsFirstElement = "registers a stream, suspends, then yields its first element"
    case oneSubscriberReversed = "gives every other subscriber the updates of overlapping applies in reverse"
    case publishesWhatIsLiveLater = "publishes, after a suspension, whatever the workout has become by then"
    case dropsHapticsUnderOverlap = "drops a logged set's haptic when another apply is inside the client"
    case judgesAnEndByWhatIsLiveLater = "decides invalidEndDate by whether a workout is live after a suspension"

    var description: String {
        rawValue
    }

    /// Faults that show only when calls overlap: whether a run meets one depends on the scheduler.
    static let racy: [SeamLateFault] = [
        .startPublishesLate, .startCommitsLate, .losingEndRepublishes, .registersBeforeItsFirstElement,
        .oneSubscriberReversed, .publishesWhatIsLiveLater, .dropsHapticsUnderOverlap, .judgesAnEndByWhatIsLiveLater
    ]
    static let sequential = allCases.filter { !racy.contains($0) }
}

/// A second `WorkoutSessionClient` written from the protocol's documentation as revised (over
/// `WorkoutEngine.reduce`, with no store), with at most one `SeamLateFault`. Without a fault it must keep
/// the contract, `invalidEndDate` included.
actor LateWrongSessionClient: WorkoutSessionClient {
    typealias Update = WorkoutSessionUpdate

    private let fault: SeamLateFault?
    private var live: WorkoutState?
    /// A start that has won and not yet committed (`startCommitsLate`).
    private var reserved: WorkoutState?
    private var lastEnded: WorkoutState?
    private var listeners: [AsyncStream<Update>.Continuation] = []
    /// Calls inside the client now: ends, and applies.
    private var ending = 0
    private var applying = 0
    private var refusedAnEnd = false
    private var pending: [Update] = []

    init(_ fault: SeamLateFault? = nil) {
        self.fault = fault
    }

    func updates() async -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream.makeStream(of: Update.self)
        guard fault == .registersBeforeItsFirstElement else {
            continuation.yield(Update(state: live))
            listeners.append(continuation)
            return stream
        }
        listeners.append(continuation)
        await letOthersIn()
        continuation.yield(Update(state: live))
        return stream
    }

    func current() -> WorkoutState? {
        live
    }

    func start(_ initial: WorkoutState) async throws {
        guard Seam.engine(nil, .started(initial), in: initial.id).0 != nil || passesTheJudge(initial) else {
            throw WorkoutSessionError.notStartable(initial.id)
        }
        if let holder = live ?? reserved {
            throw WorkoutSessionError.workoutInProgress(holder.id)
        }
        switch fault {
        case .startCommitsLate:
            reserved = initial
            publish(Update(state: initial))
            await letOthersIn()
            (live, reserved) = (initial, nil)
        case .startPublishesLate:
            live = initial
            await letOthersIn()
            publish(Update(state: initial))
        default:
            live = initial
            publish(Update(state: initial))
        }
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        guard let current = live else {
            throw WorkoutSessionError.noLiveWorkout
        }
        let (reduced, effects) = Seam.engine(current, event, in: current.id)
        guard let next = reduced, !effects.isEmpty else {
            if fault == .invalidEndThroughApplyThrows, event.isTerminal {
                throw WorkoutSessionError.invalidEndDate
            }
            return current
        }
        guard next.phase == .live else {
            return await end(next, Seam.haptics(effects))
        }
        live = next
        return await published(next, Seam.haptics(effects))
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await ended(by: .finished(endedAt: endedAt), dated: endedAt)
    }

    func discard(endedAt: Date) async throws {
        _ = try await ended(by: .discarded(endedAt: endedAt), dated: endedAt)
    }
}

/// Ending, and the `invalidEndDate` rule.
private extension LateWrongSessionClient {
    func ended(by event: WorkoutEvent, dated endedAt: Date) async throws -> WorkoutState {
        let finite = endedAt.timeIntervalSinceReferenceDate.isFinite
        if (!finite && fault == .invalidEndWhenIdle) || (refusedAnEnd && fault == .invalidEndSticks) {
            throw WorkoutSessionError.invalidEndDate
        }
        guard let before = live else {
            if fault == .losingEndRepublishes, ending > 0, let lastEnded {
                publish(Update(state: lastEnded))
            }
            throw WorkoutSessionError.noLiveWorkout
        }
        let after = try await apply(event)
        guard after.phase == .live else {
            return after
        }
        return try await refusedEnd(before, isDiscard: event.isDiscard)
    }

    /// The engine ignored the end: the workout is still live, so the call is refused (criterion 4).
    func refusedEnd(_ before: WorkoutState, isDiscard: Bool) async throws -> WorkoutState {
        refusedAnEnd = true
        switch fault {
        case .invalidEndIsNoLiveWorkout:
            throw WorkoutSessionError.noLiveWorkout
        case .invalidDiscardReturns where isDiscard:
            return before
        case .invalidEndPublishes:
            publish(Update(state: before))
        case .judgesAnEndByWhatIsLiveLater:
            await letOthersIn()
            if live == nil {
                return before
            }
        default:
            break
        }
        throw WorkoutSessionError.invalidEndDate
    }

    func end(_ next: WorkoutState, _ haptics: [Haptic]) async -> WorkoutState {
        (live, lastEnded) = (nil, next)
        publish(Update(state: next, haptics: haptics))
        ending += 1
        if fault == .losingEndRepublishes {
            await letOthersIn()
        }
        ending -= 1
        return next
    }
}

/// Publishing, snapshots and suspension.
private extension LateWrongSessionClient {
    /// Publishes the update of an apply that has been committed, as the fault has it.
    func published(_ next: WorkoutState, _ haptics: [Haptic]) async -> WorkoutState {
        applying += 1
        defer { applying -= 1 }
        switch fault {
        case .publishesWhatIsLiveLater:
            await letOthersIn()
            publish(Update(state: live, haptics: haptics))
        case .dropsHapticsUnderOverlap:
            publish(Update(state: next, haptics: applying > 1 ? [] : haptics))
            await letOthersIn()
        case .oneSubscriberReversed:
            pending.append(Update(state: next, haptics: haptics))
            await letOthersIn()
            let batch = pending
            pending = []
            for (index, listener) in listeners.enumerated() {
                (index.isMultiple(of: 2) ? batch : batch.reversed()).forEach { listener.yield($0) }
            }
        default:
            publish(Update(state: next, haptics: haptics))
        }
        return next
    }

    func publish(_ update: Update) {
        listeners.forEach { $0.yield(update) }
    }

    /// The two judges: every check `EventEnvelope.isWellFormed` makes of a snapshot but the one the fault
    /// names. Any other client asks the engine alone.
    func passesTheJudge(_ initial: WorkoutState) -> Bool {
        guard fault == .judgesAllButRestLength || fault == .judgesAllButSetDates, initial.phase == .live else {
            return false
        }
        let done = fault == .judgesAllButSetDates ? [] : initial.exercises.flatMap(\.sets).compactMap(\.doneAt)
        let dates = [initial.startedAt, initial.endedAt, initial.rest?.endsAt].compactMap(\.self) + done
            + initial.exercises.compactMap(\.lastPerformance?.date)
        let restFits = fault == .judgesAllButRestLength
            || initial.rest.map { (.zero ... WorkoutEngine.longestRest).contains($0.total) } ?? true
        return restFits && dates.allSatisfy(\.timeIntervalSinceReferenceDate.isFinite)
    }

    /// Suspends long enough for every caller already on its way to enter the actor.
    func letOthersIn() async {
        for _ in 0 ..< 400 {
            await Task.yield()
        }
    }
}

extension WorkoutEvent {
    var isDiscard: Bool {
        if case .discarded = self {
            return true
        }
        return false
    }

    var isTerminal: Bool {
        if case .finished = self {
            return true
        }
        return isDiscard
    }
}
