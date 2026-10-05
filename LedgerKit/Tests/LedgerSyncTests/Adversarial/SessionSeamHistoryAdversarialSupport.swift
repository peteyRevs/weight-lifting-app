import Foundation
import LedgerDomain
import LedgerTestSupport

/// A stream read back as a history of the engine, for the suites that apply from many tasks at once: sets
/// added and then logged, each set by one task. Whatever order the calls landed in, each update must be
/// `reduce` of the one before with exactly one of the events.
struct SeamHistory {
    /// The state published for each event, by the event.
    private(set) var published: [WorkoutEvent: WorkoutState] = [:]
    /// What was wrong with the stream, if anything.
    private(set) var fault: String?

    /// - Parameters:
    ///   - updates: a stream from its first element on.
    ///   - adds: the add event of every set the tasks added, by set.
    init(_ updates: [WorkoutSessionUpdate], adds: [SetID: WorkoutEvent]) {
        guard var state = updates.first?.state, updates.first?.haptics == [] else {
            fault = "no first element, or one with effects"
            return
        }
        for (index, update) in updates.dropFirst().enumerated() {
            guard let event = Self.event(from: state, to: update, adds: adds), let next = update.state else {
                fault = "update \(index + 1) is not the engine's for any event still to come"
                return
            }
            guard published.updateValue(next, forKey: event) == nil else {
                fault = "update \(index + 1) repeats an event"
                return
            }
            state = next
        }
    }

    /// The one event that takes `before` to `after`: the add of the set `after` gained, or the log of the
    /// set that became done. `nil` when the engine's update for that event is not `after`.
    private static func event(
        from before: WorkoutState,
        to after: WorkoutSessionUpdate,
        adds: [SetID: WorkoutEvent]
    ) -> WorkoutEvent? {
        let held = Set(before.exercises.flatMap(\.sets).map(\.id))
        let done = Set(before.exercises.flatMap(\.sets).filter(\.isDone).map(\.id))
        let sets = after.state?.exercises.flatMap(\.sets) ?? []
        let changed = sets.first { !held.contains($0.id) } ?? sets.first { $0.isDone && !done.contains($0.id) }
        guard let changed, let add = adds[changed.id] else {
            return nil
        }
        let event = held.contains(changed.id) ? Seam.logging(add) : add
        return Seam.update(after: event, on: before) == after ? event : nil
    }
}

extension Seam {
    /// The log of the set an add event added: done a minute in, at its own weight and reps.
    static func logging(_ add: WorkoutEvent) -> WorkoutEvent {
        guard case let .setAdded(exerciseIndex, set) = add else {
            return add
        }
        return .setLogged(
            exerciseIndex: exerciseIndex,
            setID: set.id,
            weight: set.weight,
            reps: set.reps,
            doneAt: at(60)
        )
    }

    /// The add events of sets `numbers`, spread over the five exercises of the seed session, by set.
    static func adds(_ numbers: Range<Int>) -> [SetID: WorkoutEvent] {
        Dictionary(uniqueKeysWithValues: numbers.map { number in
            let set = freshSet(number)
            return (set.id, WorkoutEvent.setAdded(exerciseIndex: number % 5, set: set))
        })
    }

    /// `count` stepper edits of the first row, each to a weight no other has, with the engine's updates.
    static func edits(_ count: Int, from live: WorkoutState) -> (events: [WorkoutEvent], updates: [Seam.Update]) {
        var state = live
        var events: [WorkoutEvent] = []
        var updates: [Seam.Update] = []
        for number in 1 ... count {
            let setID = state.exercises[0].sets[0].id
            let event = WorkoutEvent.setTargetChanged(
                exerciseIndex: 0,
                setID: setID,
                weight: .pounds(Decimal(number)),
                reps: nil
            )
            guard let update = Seam.update(after: event, on: state), let next = update.state else {
                continue
            }
            state = next
            events.append(event)
            updates.append(update)
        }
        return (events, updates)
    }
}
