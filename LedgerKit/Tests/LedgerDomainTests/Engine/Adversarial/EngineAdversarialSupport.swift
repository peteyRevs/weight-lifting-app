import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

// Helpers for the F04 adversarial pass. They only build inputs and fold them; every expected value
// in the suites is derived from the F04 brief, ADR-004 and the spec, never from the engine.

/// `seconds` after `EventBuilders.start` (2026-09-16T05:20:00Z).
func engineTime(_ seconds: Double) -> Date {
    EventBuilders.start.addingTimeInterval(seconds)
}

enum EngineAdv {
    static let phone = EventBuilders.phone
    static let watch = EventBuilders.watch
    /// A third device (an iPad running the iPhone app). Its ID sorts after the watch's.
    static let tablet = DeviceID(EventBuilders.uuid(0xF003))
    static let workoutID = EventBuilders.workoutID

    /// The set ID of row `set` of exercise `exercise` in an `EventBuilders` session.
    static func sid(_ exercise: Int, _ set: Int) -> SetID {
        EventBuilders.setID(exercise, set)
    }

    static func env(
        _ event: WorkoutEvent,
        _ device: DeviceID = phone,
        seq: UInt64,
        at seconds: Double,
        workoutID: WorkoutID = workoutID
    ) -> EventEnvelope {
        EventEnvelope(event: event, workoutID: workoutID, device: device, seq: seq, wallClock: engineTime(seconds))
    }

    /// The `started` envelope for `state` (default: the spec §6.3 seed session).
    static func start(
        _ state: WorkoutState = EventBuilders.seedSession(),
        _ device: DeviceID = phone,
        seq: UInt64 = 1,
        at seconds: Double = 0
    ) -> EventEnvelope {
        env(.started(state), device, seq: seq, at: seconds, workoutID: state.id)
    }

    /// `setLogged` for row (`exercise`, `set`) of an `EventBuilders` session.
    static func logged(
        _ exercise: Int,
        _ set: Int,
        pounds text: String = "185",
        reps: Int = 5,
        doneAt seconds: Double
    ) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exercise,
            setID: sid(exercise, set),
            weight: pounds(text),
            reps: Reps(clamping: reps),
            doneAt: engineTime(seconds)
        )
    }

    /// Folds `envelopes` with `reduce` in the order given: the final state and each step's effects.
    static func fold(
        _ envelopes: [EventEnvelope],
        from initial: WorkoutState? = nil
    ) -> (state: WorkoutState?, effects: [[Effect]]) {
        var state = initial
        var effects: [[Effect]] = []
        for envelope in envelopes {
            let (next, emitted) = WorkoutEngine.reduce(state, envelope)
            state = next
            effects.append(emitted)
        }
        return (state, effects)
    }

    /// Folds and returns only the final state.
    static func state(after envelopes: [EventEnvelope], from initial: WorkoutState? = nil) -> WorkoutState? {
        fold(envelopes, from: initial).state
    }

    /// Row (`exercise`, `set`) of `state`, or `nil` when it does not exist.
    static func row(_ state: WorkoutState?, _ exercise: Int, _ set: Int) -> LoggedSet? {
        guard let state, state.exercises.indices.contains(exercise),
              state.exercises[exercise].sets.indices.contains(set)
        else {
            return nil
        }
        return state.exercises[exercise].sets[set]
    }

    /// The effects as a multiset: exact contents and counts, order ignored.
    static func bag(_ effects: [Effect]) -> [Effect: Int] {
        effects.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// `true` when `effects` schedule a rest-over notification.
    static func schedulesRest(_ effects: [Effect]) -> Bool {
        effects.contains { effect in
            guard case .scheduleRestNotification = effect else {
                return false
            }
            return true
        }
    }

    /// `true` when `effects` play any haptic.
    static func buzzes(_ effects: [Effect]) -> Bool {
        effects.contains { effect in
            guard case .haptic = effect else {
                return false
            }
            return true
        }
    }

    static func cursor(_ exercise: Int, _ set: Int) -> Cursor {
        Cursor(exerciseIndex: exercise, setIndex: set)
    }

    static func spec(
        _ name: String,
        sets: Int,
        rest: Int,
        superset: Bool = false,
        drop: Bool = false
    ) -> EventBuilders.ExerciseSpec {
        EventBuilders.ExerciseSpec(
            name, .dumbbell, sets: sets, reps: 8, pounds: 50, restSeconds: rest, superset: superset, dropSet: drop
        )
    }
}

/// One device's outgoing envelopes: `seq` 1, 2, 3 … in the order it records them.
struct DeviceRecorder {
    let device: DeviceID
    private(set) var seq: UInt64 = 0
    private(set) var recorded: [EventEnvelope] = []

    init(_ device: DeviceID, firstSeq: UInt64 = 1) {
        self.device = device
        seq = firstSeq - 1
    }

    @discardableResult
    mutating func record(_ event: WorkoutEvent, at wallClock: Date) -> EventEnvelope {
        seq += 1
        let envelope = EventEnvelope(
            event: event, workoutID: EngineAdv.workoutID, device: device, seq: seq, wallClock: wallClock
        )
        recorded.append(envelope)
        return envelope
    }
}

/// A device as ADR-004 rule 2 describes it: it keeps one envelope per key, applies an envelope that
/// sorts after everything it has applied with `reduce`, and otherwise rebuilds the state from the
/// merged, sorted log with `replay`.
struct Replica {
    private(set) var log: [EnvelopeKey: EventEnvelope] = [:]
    private(set) var state: WorkoutState?
    private(set) var newest: EventEnvelope?
    private(set) var rebuilds = 0

    init(_ envelopes: [EventEnvelope] = []) {
        for envelope in envelopes {
            receive(envelope)
        }
    }

    var envelopes: [EventEnvelope] {
        Array(log.values)
    }

    mutating func receive(_ envelope: EventEnvelope) {
        guard log[envelope.key] == nil else {
            return
        }
        log[envelope.key] = envelope
        if state != nil, let newest, newest < envelope {
            state = WorkoutEngine.reduce(state, envelope).0
            self.newest = envelope
        } else {
            state = WorkoutEngine.replay(envelopes)
            newest = log.values.max()
            rebuilds += 1
        }
    }
}

extension SeededGenerator {
    /// A random (seeded) UUID.
    mutating func uuid() -> UUID {
        let high = next()
        let low = next()
        func byte(_ word: UInt64, _ index: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: word >> (8 * index))
        }
        return UUID(uuid: (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ))
    }

    /// `true` with probability `percent` / 100.
    mutating func chance(_ percent: Int) -> Bool {
        Int.random(in: 0 ..< 100, using: &self) < percent
    }
}
