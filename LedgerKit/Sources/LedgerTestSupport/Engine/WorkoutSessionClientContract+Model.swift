import Foundation
import LedgerDomain

/// The contract's rules as a model: what each call returns or throws and the update it publishes. The seeded
/// scripts run it beside a client (`scriptViolation`), and the clauses whose calls race ask it what the call
/// that won must have done.
public extension WorkoutSessionClientContract {
    /// One call on a client.
    enum Step: Sendable, CustomStringConvertible {
        case start(WorkoutState)
        case apply(WorkoutEvent)
        case finish(endedAt: Date)
        case discard(endedAt: Date)

        /// The call and, for an event, its case: a snapshot's or an event's payload would fill the page.
        public var description: String {
            switch self {
            case let .start(snapshot):
                return "start(\(snapshot.phase) workout \(snapshot.id.rawValue.uuidString.suffix(4)))"
            case let .apply(event):
                let name = String(describing: event).prefix { $0 != "(" }
                return "apply(.\(name))"
            case .finish:
                return "finish"
            case .discard:
                return "discard"
            }
        }
    }
}

extension WorkoutSessionClientContract {
    /// How a call ended.
    enum Outcome: Equatable, Sendable, CustomStringConvertible {
        /// `start` or `discard` returned.
        case done
        /// `apply` or `finish` returned this state.
        case state(WorkoutState)
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
            case .done: "returned"
            case let .state(state): "returned a \(brief(Update(state: state)))"
            case let .threw(error): "threw \(error)"
            }
        }

        static func refused(_ error: WorkoutSessionError) -> Outcome {
            .threw("\(error)")
        }
    }

    /// The live workout and, for each call, what it returns or throws and the update it publishes, if any.
    struct Model {
        private(set) var live: WorkoutState?

        mutating func perform(_ step: Step) -> (outcome: Outcome, published: Update?) {
            switch step {
            case let .start(snapshot):
                // The snapshot is judged before the session: `notStartable` wins over `workoutInProgress`.
                guard let started = engineUpdate(nil, .started(snapshot), in: snapshot.id) else {
                    return (.refused(.notStartable(snapshot.id)), nil)
                }
                if let workout = live {
                    return (.refused(.workoutInProgress(workout.id)), nil)
                }
                live = started.state
                return (.done, started)
            case let .apply(event):
                return apply(event) { .state($0) }
            case let .finish(endedAt):
                return end(.finished(endedAt: endedAt)) { .state($0) }
            case let .discard(endedAt):
                return end(.discarded(endedAt: endedAt)) { _ in .done }
            }
        }

        /// An event on the live workout: refused when there is none; returned unchanged and unpublished
        /// when the engine ignores it; otherwise published, and the end of the workout when it is terminal.
        private mutating func apply(
            _ event: WorkoutEvent,
            returning outcome: (WorkoutState) -> Outcome
        ) -> (outcome: Outcome, published: Update?) {
            guard let workout = live else {
                return (.refused(.noLiveWorkout), nil)
            }
            guard let update = engineUpdate(workout, event, in: workout.id), let next = update.state else {
                return (outcome(workout), nil)
            }
            live = update.live
            return (outcome(next), update)
        }

        /// `finish` and `discard`: the terminal event, and a refusal when the workout is still live after
        /// it, because the engine ignored the end.
        private mutating func end(
            _ event: WorkoutEvent,
            returning outcome: (WorkoutState) -> Outcome
        ) -> (outcome: Outcome, published: Update?) {
            let wasLive = live != nil
            let result = apply(event, returning: outcome)
            return wasLive && live != nil ? (.refused(.invalidEndDate), nil) : result
        }
    }

    /// How `step` ended on `client`.
    static func outcome(of step: Step, on client: Client) async -> Outcome {
        do {
            switch step {
            case let .start(snapshot):
                try await client.start(snapshot)
                return .done
            case let .apply(event):
                return try await .state(client.apply(event))
            case let .finish(endedAt):
                return try await .state(client.finish(endedAt: endedAt))
            case let .discard(endedAt):
                try await client.discard(endedAt: endedAt)
                return .done
            }
        } catch {
            return .threw("\(error)")
        }
    }
}
