import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded inputs for the F04 property tests: sessions, intent-driven events and garbage.
enum EngineGen {
    static let restChoices = [30, 60, 75, 90, 120, 150, 300]
    static let poundChoices = ["0", "45", "52.5", "55", "185", "187.5", "242.25"]

    /// 1–6 exercises of 1–5 working sets, random supersets of 2–3 members (unequal set counts),
    /// random drop sets, random auto-rest.
    static func session(using generator: inout SeededGenerator, allowEmpty: Bool = false) -> WorkoutState {
        let count = Int.random(in: 1 ... 6, using: &generator)
        var specs: [EventBuilders.ExerciseSpec] = []
        var chain = 1
        for index in 0 ..< count {
            let joins = index > 0 && chain < 3 && generator.chance(40)
            chain = joins ? chain + 1 : 1
            let minimum = allowEmpty ? 0 : 1
            specs.append(EngineAdv.spec(
                "Exercise \(index)",
                sets: Int.random(in: minimum ... 5, using: &generator),
                rest: restChoices.randomElement(using: &generator) ?? 90,
                superset: joins,
                drop: generator.chance(20)
            ))
        }
        return EventBuilders.session(specs, autoRest: generator.chance(80))
    }

    /// Every set ID of `state` with its exercise index.
    static func setIDs(of state: WorkoutState) -> [(exercise: Int, id: SetID)] {
        state.exercises.enumerated().flatMap { index, exercise in exercise.sets.map { (index, $0.id) } }
    }

    static func weight(using generator: inout SeededGenerator) -> Weight {
        pounds(poundChoices.randomElement(using: &generator) ?? "185")
    }

    static func reps(using generator: inout SeededGenerator) -> Reps {
        Reps(clamping: Int.random(in: 1 ... 15, using: &generator))
    }

    /// An event a user of `state` could plausibly cause at `now` (mostly valid, some stale or out of
    /// range). `sharedAddIDs` are set IDs any device may reuse, to model two devices adding "the same" set.
    static func intent(
        for state: WorkoutState,
        at now: Date,
        sharedAddIDs: [SetID],
        using generator: inout SeededGenerator
    ) -> WorkoutEvent {
        let rows = setIDs(of: state)
        let pick = rows.randomElement(using: &generator)
        let exercise = pick?.exercise ?? 0
        let setID = pick?.id ?? SetID(generator.uuid())
        switch Int.random(in: 0 ..< 100, using: &generator) {
        case 0 ..< 30:
            if generator.chance(60), let logged = cursorLog(in: state, at: now) {
                return logged
            }
            return .setLogged(
                exerciseIndex: exercise, setID: setID, weight: weight(using: &generator),
                reps: reps(using: &generator), doneAt: now
            )
        case 30 ..< 38:
            return .setUnlogged(exerciseIndex: exercise, setID: setID)
        case 38 ..< 50:
            return .setTargetChanged(
                exerciseIndex: exercise, setID: setID,
                weight: generator.chance(60) ? weight(using: &generator) : nil,
                reps: generator.chance(50) ? reps(using: &generator) : nil
            )
        default:
            return otherIntent(for: state, at: now, exercise: exercise, sharedAddIDs: sharedAddIDs, using: &generator)
        }
    }

    /// "Done set" on the row under the cursor, with its current values.
    private static func cursorLog(in state: WorkoutState, at now: Date) -> WorkoutEvent? {
        guard let cursor = state.cursor, let row = EngineAdv.row(state, cursor.exerciseIndex, cursor.setIndex) else {
            return nil
        }
        return .setLogged(
            exerciseIndex: cursor.exerciseIndex, setID: row.id, weight: row.weight, reps: row.reps, doneAt: now
        )
    }

    private static func otherIntent(
        for state: WorkoutState,
        at now: Date,
        exercise: Int,
        sharedAddIDs: [SetID],
        using generator: inout SeededGenerator
    ) -> WorkoutEvent {
        switch Int.random(in: 0 ..< 50, using: &generator) {
        case 0 ..< 6:
            let id = generator.chance(30) ? sharedAddIDs.randomElement(using: &generator) : nil
            let set = LoggedSet(
                id: id ?? SetID(generator.uuid()), weight: weight(using: &generator),
                reps: reps(using: &generator), kind: .added
            )
            return .setAdded(exerciseIndex: exercise, set: set)
        case 6 ..< 10:
            return .allSetsRepeated(
                exerciseIndex: exercise,
                weight: weight(using: &generator),
                reps: reps(using: &generator)
            )
        case 10 ..< 14:
            return .exerciseSwapped(
                exerciseIndex: exercise, exerciseID: ExerciseID(EventBuilders.uuid(0xA000 + Int.random(
                    in: 0 ... 3,
                    using: &generator
                ))),
                name: "Swap", alsoUpdateProgram: generator.chance(50)
            )
        case 14 ..< 22:
            let limit = max(1, state.exercises.count + 1)
            return .exerciseSelected(
                exerciseIndex: Int.random(in: -1 ... limit, using: &generator),
                setIndex: Int.random(in: -1 ... 6, using: &generator)
            )
        case 22 ..< 30:
            let seconds = Double(restChoices.randomElement(using: &generator) ?? 90)
            return .restStarted(endsAt: now.addingTimeInterval(seconds), total: .seconds(seconds))
        case 30 ..< 40:
            return plus30(on: state, at: now)
        case 40 ..< 46:
            return .restSkipped
        case 46 ..< 48:
            return .finished(endedAt: now)
        default:
            return .discarded(endedAt: now)
        }
    }
}

extension EngineGen {
    /// "+30s" as the device holding `state` sends it when its clock reads `now` (fix round 2, decision
    /// B): its screen shows the rest running while some of it remains.
    static func plus30(on state: WorkoutState, at now: Date) -> WorkoutEvent {
        let shown = state.rest.map { $0.remaining(at: now) > .zero } ?? false
        return .restExtended(amount: .seconds(30), extendsShownRest: shown, tappedAt: now)
    }
}

/// A random multi-device history: devices take turns acting on their own replica, with skewed
/// clocks, ties and partitions. Returns every envelope recorded.
struct EngineScenario {
    var replicas: [DeviceID: Replica] = [:]
    var recorders: [DeviceID: DeviceRecorder] = [:]
    var skews: [DeviceID: Double] = [:]
    let devices: [DeviceID]
    let snapshot: WorkoutState
    let sharedAddIDs: [SetID]
    var realTime: Double = 0

    init(devices: [DeviceID], snapshot: WorkoutState, using generator: inout SeededGenerator) {
        self.devices = devices
        self.snapshot = snapshot
        sharedAddIDs = [SetID(generator.uuid()), SetID(generator.uuid())]
        for device in devices {
            recorders[device] = DeviceRecorder(device)
            replicas[device] = Replica()
            // Most devices agree to the second; some run a few seconds off (ties stay possible).
            skews[device] = generator.chance(60) ? 0 : Double(Int.random(in: -8 ... 8, using: &generator))
        }
    }

    var all: [EventEnvelope] {
        recorders.values.flatMap(\.recorded)
    }

    /// The first device starts the workout and every device receives the `started`.
    mutating func start() {
        guard let first = devices.first, var recorder = recorders[first] else {
            return
        }
        let started = recorder.record(.started(snapshot), at: engineTime(skews[first] ?? 0))
        recorders[first] = recorder
        deliver(started, to: devices)
    }

    /// `device` acts on its own replica once; returns the envelope.
    @discardableResult
    mutating func act(_ device: DeviceID, using generator: inout SeededGenerator) -> EventEnvelope? {
        guard var recorder = recorders[device] else {
            return nil
        }
        let state = replicas[device]?.state ?? snapshot
        if !generator.chance(25) {
            realTime += Double(Int.random(in: 1 ... 12, using: &generator))
        }
        let now = engineTime(realTime + (skews[device] ?? 0))
        let event = EngineGen.intent(for: state, at: now, sharedAddIDs: sharedAddIDs, using: &generator)
        let envelope = recorder.record(event, at: now)
        recorders[device] = recorder
        deliver(envelope, to: [device])
        return envelope
    }

    mutating func deliver(_ envelope: EventEnvelope, to targets: [DeviceID]) {
        for target in targets {
            replicas[target]?.receive(envelope)
        }
    }

    /// Heals the partition: every device receives every envelope, shuffled, some twice.
    mutating func heal(using generator: inout SeededGenerator) {
        for device in devices {
            var inbox = all + all.filter { _ in generator.chance(20) }
            inbox.shuffle(using: &generator)
            for envelope in inbox {
                replicas[device]?.receive(envelope)
            }
        }
    }
}
