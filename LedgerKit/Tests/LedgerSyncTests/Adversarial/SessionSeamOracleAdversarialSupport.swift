import Foundation
import LedgerDomain
import LedgerTestSupport

/// One call on a `WorkoutSessionClient`.
enum SeamCall: Sendable, CustomStringConvertible {
    case start(WorkoutState)
    case apply(WorkoutEvent)
    case finish(Date)
    case discard(Date)

    /// The event a client was asked for, as `FakeWorkoutSessionClient.applied` lists it.
    var event: WorkoutEvent {
        switch self {
        case let .start(snapshot): .started(snapshot)
        case let .apply(event): event
        case let .finish(endedAt): .finished(endedAt: endedAt)
        case let .discard(endedAt): .discarded(endedAt: endedAt)
        }
    }

    /// The call and its event's case: a payload would fill the page.
    var description: String {
        let payload = String(describing: event)
        let name = payload.prefix { $0 != "(" }
        switch self {
        case let .start(snapshot): return "start(\(snapshot.phase) \(snapshot.id.rawValue.uuidString.suffix(6)))"
        case .apply: return "apply(.\(name))"
        case let .finish(endedAt): return "finish(\(endedAt.timeIntervalSinceReferenceDate))"
        case let .discard(endedAt): return "discard(\(endedAt.timeIntervalSinceReferenceDate))"
        }
    }
}

/// How a call ended.
enum SeamOutcome: Equatable, CustomStringConvertible {
    /// `start` or `discard` returned.
    case returned
    /// `apply` or `finish` returned this state.
    case state(WorkoutState)
    case refused(WorkoutSessionError)
    /// It threw something that is not a `WorkoutSessionError`.
    case threw(String)

    /// The state `apply` or `finish` returned, if it returned one.
    var state: WorkoutState? {
        if case let .state(state) = self {
            return state
        }
        return nil
    }

    var description: String {
        switch self {
        case .returned: "returned"
        case let .state(state): "returned \(Seam.brief(WorkoutSessionUpdate(state: state)))"
        case let .refused(error): "threw \(error)"
        case let .threw(error): "threw \(error), which is no WorkoutSessionError"
        }
    }
}

/// The seam's rules as the brief states them (F10 "Plan amendments", slice S1, criteria 1–4, and the
/// protocol's documentation), over the real engine: what each call returns or throws, the update it
/// publishes, and the live workout afterwards.
struct SeamOracle {
    private(set) var live: WorkoutState?
    /// Every event a client was asked for, in call order.
    private(set) var asked: [WorkoutEvent] = []

    init(live: WorkoutState? = nil) {
        self.live = live
    }

    mutating func perform(_ call: SeamCall) -> (outcome: SeamOutcome, published: WorkoutSessionUpdate?) {
        asked.append(call.event)
        switch call {
        case let .start(snapshot):
            return start(snapshot)
        case let .apply(event):
            return apply(event)
        case let .finish(endedAt):
            return end(.finished(endedAt: endedAt))
        case let .discard(endedAt):
            let (outcome, published) = end(.discarded(endedAt: endedAt))
            if case .state = outcome {
                return (.returned, published)
            }
            return (outcome, published)
        }
    }

    /// Criterion 4, as revised after round 1: an end the engine ignores (nothing published, the workout
    /// still live) is refused with `invalidEndDate` by `finish` and `discard`.
    private mutating func end(_ event: WorkoutEvent) -> (SeamOutcome, WorkoutSessionUpdate?) {
        let (outcome, published) = apply(event)
        if case .state = outcome, published == nil {
            return (.refused(.invalidEndDate), nil)
        }
        return (outcome, published)
    }

    /// Criterion 2: a snapshot the engine would not start is `notStartable`, live workout or not; then a
    /// live workout refuses any other; else the snapshot becomes current and is published without effects
    /// (a start plays no haptic).
    private mutating func start(_ snapshot: WorkoutState) -> (SeamOutcome, WorkoutSessionUpdate?) {
        let (started, effects) = Seam.engine(nil, .started(snapshot), in: snapshot.id)
        guard let started else {
            return (.refused(.notStartable(snapshot.id)), nil)
        }
        if let live {
            return (.refused(.workoutInProgress(live.id)), nil)
        }
        live = started
        return (.returned, WorkoutSessionUpdate(state: started, haptics: Seam.haptics(effects)))
    }

    /// Criteria 2 to 4: refused with nothing live; unchanged and unpublished when the engine ignores the
    /// event (no effects at all, ADR-004); otherwise returned and published once, with the haptics, and
    /// the end of the workout when the event is terminal.
    private mutating func apply(_ event: WorkoutEvent) -> (SeamOutcome, WorkoutSessionUpdate?) {
        guard let current = live else {
            return (.refused(.noLiveWorkout), nil)
        }
        let (reduced, effects) = Seam.engine(current, event, in: current.id)
        guard let next = reduced, !effects.isEmpty else {
            return (.state(current), nil)
        }
        live = next.phase == .live ? next : nil
        return (.state(next), WorkoutSessionUpdate(state: next, haptics: Seam.haptics(effects)))
    }
}

extension Seam {
    /// How `call` ended on `client`.
    static func outcome(of call: SeamCall, on client: any WorkoutSessionClient) async -> SeamOutcome {
        do {
            switch call {
            case let .start(snapshot):
                try await client.start(snapshot)
                return .returned
            case let .apply(event):
                return try await .state(client.apply(event))
            case let .finish(endedAt):
                return try await .state(client.finish(endedAt: endedAt))
            case let .discard(endedAt):
                try await client.discard(endedAt: endedAt)
                return .returned
            }
        } catch let error as WorkoutSessionError {
            return .refused(error)
        } catch {
            return .threw(String(describing: error))
        }
    }

    /// Whether two event lists are the same, counting a date that is not a number as equal to itself
    /// (`Date`'s `==` does not).
    static func sameEvents(_ one: [WorkoutEvent], _ other: [WorkoutEvent]) -> Bool {
        one.count == other.count && zip(one, other).allSatisfy { pair in
            pair.0 == pair.1 || String(reflecting: pair.0) == String(reflecting: pair.1)
        }
    }
}
