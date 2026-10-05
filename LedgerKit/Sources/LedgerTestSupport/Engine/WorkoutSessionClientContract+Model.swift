import Foundation
import LedgerDomain

/// The contract's rules as a model, which the seeded scripts run beside a client (`scriptViolation`).
extension WorkoutSessionClientContract {
    /// How a call ended.
    enum Outcome: Equatable, CustomStringConvertible {
        /// `start` or `discard` returned.
        case done
        /// `apply` or `finish` returned this state.
        case state(WorkoutState)
        case threw(String)

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
                return apply(.finished(endedAt: endedAt)) { .state($0) }
            case let .discard(endedAt):
                return apply(.discarded(endedAt: endedAt)) { _ in .done }
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
