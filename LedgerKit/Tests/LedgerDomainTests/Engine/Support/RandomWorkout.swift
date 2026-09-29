import Foundation
@testable import LedgerDomain
import LedgerTestSupport

/// Random live workouts for the engine's property tests, from a seeded generator (testing-strategy
/// §3 rule 5).
///
/// A log starts with a phone or watch `started` and continues with envelopes from both devices:
/// seq counts up per device and wall clocks never go backwards but may tie. Most events are valid;
/// some aim at a missing exercise or set, add a duplicate set, start twice, or end the workout
/// early so that later envelopes must be ignored.
struct RandomWorkout {
    private var rng: SeededGenerator
    private var nextAddedSet = 0

    init(seed: PropertySeed) {
        rng = seed.generator
    }

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
    }

    /// 1–5 exercises of 1–4 working sets; some have a drop row, some join a superset.
    mutating func session() -> WorkoutState {
        let specs = (0 ..< int(1 ... 5)).map { index in
            EventBuilders.ExerciseSpec(
                "Exercise \(index)",
                pick(Equipment.allCases),
                sets: int(1 ... 4),
                reps: int(3 ... 12),
                pounds: pick([45, 100, 185, dec("202.5")]),
                restSeconds: pick([30, 60, 75, 90, 150]),
                superset: index > 0 && chance(40),
                dropSet: chance(25)
            )
        }
        return EventBuilders.session(specs, autoRest: chance(80))
    }

    /// A started session followed by `steps` random envelopes.
    mutating func log(steps: Int) -> [EventEnvelope] {
        let session = session()
        let devices = [EventBuilders.phone, EventBuilders.watch]
        var seqs = [EventBuilders.phone: UInt64(0), EventBuilders.watch: 0]
        var setIDs = session.exercises.map { $0.sets.map(\.id) }
        var clock = EventBuilders.start
        var log: [EventEnvelope] = []
        for step in 0 ... steps {
            let device = pick(devices)
            seqs[device, default: 0] += 1
            let event = step == 0 ? .started(session) : event(for: session, setIDs: &setIDs, at: clock)
            log.append(EventBuilders.envelope(event, device: device, seq: seqs[device, default: 0], at: clock))
            // The first step after the start moves the clock, so `started` sorts first.
            clock = clock.addingTimeInterval(Double(step == 0 ? int(1 ... 20) : int(0 ... 20)))
        }
        return log
    }

    /// `log` in a random order.
    mutating func shuffled(_ log: [EventEnvelope]) -> [EventEnvelope] {
        log.shuffled(using: &rng)
    }

    private mutating func event(for session: WorkoutState, setIDs: inout [[SetID]], at time: Date) -> WorkoutEvent {
        let exerciseIndex = chance(92) ? int(0 ... setIDs.count - 1) : pick([-1, setIDs.count])
        let roll = int(0 ... 99)
        switch roll {
        case 0 ..< 36:
            return setEvent(roll, exerciseIndex: exerciseIndex, setIDs: setIDs, at: time)
        case 36 ..< 44:
            return addedSet(to: exerciseIndex, setIDs: &setIDs)
        case 44 ..< 48:
            return .allSetsRepeated(exerciseIndex: exerciseIndex, weight: weight(), reps: reps())
        case 48 ..< 53:
            let exerciseID = ExerciseID(EventBuilders.uuid(0xE100 + int(0 ... 3)))
            return .exerciseSwapped(
                exerciseIndex: exerciseIndex,
                exerciseID: exerciseID,
                name: "Swap",
                alsoUpdateProgram: chance(50)
            )
        case 53 ..< 62:
            return .exerciseSelected(exerciseIndex: exerciseIndex, setIndex: int(-1 ... 5))
        default:
            return clockEvent(roll, session: session, at: time)
        }
    }

    private mutating func setEvent(_ roll: Int, exerciseIndex: Int, setIDs: [[SetID]], at time: Date) -> WorkoutEvent {
        let setID = setID(in: exerciseIndex, of: setIDs)
        switch roll {
        case 0 ..< 22:
            return .setLogged(exerciseIndex: exerciseIndex, setID: setID, weight: weight(), reps: reps(), doneAt: time)
        case 22 ..< 28:
            return .setUnlogged(exerciseIndex: exerciseIndex, setID: setID)
        default:
            let weight = chance(60) ? weight() : nil
            return .setTargetChanged(
                exerciseIndex: exerciseIndex,
                setID: setID,
                weight: weight,
                reps: chance(60) ? reps() : nil
            )
        }
    }

    private mutating func clockEvent(_ roll: Int, session: WorkoutState, at time: Date) -> WorkoutEvent {
        switch roll {
        case 62 ..< 71:
            let seconds = int(30 ... 200)
            return .restStarted(endsAt: time.addingTimeInterval(Double(seconds)), total: .seconds(seconds))
        case 71 ..< 83:
            return .restExtended(amount: .seconds(pick([15, 30, 45])), extendsShownRest: chance(70), tappedAt: time)
        case 83 ..< 90:
            return .restSkipped
        case 90 ..< 92:
            return .started(session)
        case 92:
            return .finished(endedAt: time)
        case 93:
            return .discarded(endedAt: time)
        default:
            return .setLogged(
                exerciseIndex: 0,
                setID: EventBuilders.setID(0, 0),
                weight: weight(),
                reps: reps(),
                doneAt: time
            )
        }
    }

    /// Mostly a set of this exercise; sometimes one of another exercise or an unknown ID.
    private mutating func setID(in exerciseIndex: Int, of setIDs: [[SetID]]) -> SetID {
        let own = setIDs.indices.contains(exerciseIndex) ? setIDs[exerciseIndex] : []
        switch int(0 ... 99) {
        case 0 ..< 85 where !own.isEmpty:
            return pick(own)
        case 0 ..< 95:
            return pick(pick(setIDs))
        default:
            return SetID(EventBuilders.uuid(0xDEAD))
        }
    }

    /// A new `.added` set, or (one time in five) a copy of an existing ID.
    private mutating func addedSet(to exerciseIndex: Int, setIDs: inout [[SetID]]) -> WorkoutEvent {
        let id: SetID
        if chance(20) {
            id = pick(pick(setIDs))
        } else {
            nextAddedSet += 1
            id = SetID(EventBuilders.uuid(0x50000 + nextAddedSet))
            if setIDs.indices.contains(exerciseIndex) {
                setIDs[exerciseIndex].append(id)
            }
        }
        let kind = pick(SetKind.allCases)
        return .setAdded(
            exerciseIndex: exerciseIndex,
            set: LoggedSet(id: id, weight: weight(), reps: reps(), kind: kind)
        )
    }
}

// MARK: - Primitive draws

private extension RandomWorkout {
    mutating func weight() -> Weight {
        .pounds(pick([-5, 0, 45, 100, 185, dec("202.5")]))
    }

    mutating func reps() -> Reps {
        Reps(clamping: int(1 ... 15))
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &rng)
    }

    mutating func chance(_ percent: Int) -> Bool {
        int(0 ... 99) < percent
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[int(0 ... values.count - 1)]
    }
}
