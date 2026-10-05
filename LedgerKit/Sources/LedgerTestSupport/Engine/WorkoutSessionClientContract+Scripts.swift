import Foundation
import LedgerDomain

/// Seeded scripts: long runs of calls, checked against the clauses' rules written as a model. A clause shows
/// one rule on one short sequence; a script meets the rules in orders nobody wrote down (a refused start
/// between two sets, an ignored event before a finish, a second workout after a discard).
public extension WorkoutSessionClientContract {
    /// One call a script makes.
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

    /// The script of `seed`: `count` calls drawn from a generator the seed alone decides (testing-strategy §3
    /// rule 5), so the same seed is always the same script. It starts workouts, edits and logs their sets,
    /// runs rests, and ends them by `finish`, `discard` and terminal events through `apply`; and it makes the
    /// calls a client must refuse or ignore: a start on a live workout or with an ended snapshot, a call with
    /// nothing live, a row that does not exist, a date that is not finite, a rest that is too long.
    static func script(seed: UInt64, count: Int = 80) -> [Step] {
        var writer = ScriptWriter(random: ScriptGenerator(seed: seed))
        return (0 ..< count).map { _ in writer.next() }
    }

    /// Runs `script(seed:)` on `client`, a fresh one, beside the model. `nil` when every call returned or
    /// threw what the rules say, `current()` agreed after each, and two streams carried exactly the rules'
    /// updates: one opened before the first call, and one opened before a later call the seed picks, which
    /// starts with the workout as it stood then, without effects. Else the first thing that differed.
    static func scriptViolation(seed: UInt64, on client: Client) async throws -> String? {
        let steps = script(seed: seed)
        let joining = Int(seed % UInt64(steps.count))
        var model = Model()
        var early = await Subscriber(client)
        var late: Subscriber?
        var expected = (early: [Update(state: nil)], late: [Update]())
        for (number, step) in steps.enumerated() {
            if number == joining {
                late = await Subscriber(client)
                expected.late = [Update(state: model.live)]
            }
            let (ruled, published) = model.perform(step)
            let actual = await outcome(of: step, on: client)
            guard actual == ruled else {
                return "step \(number), \(step): \(actual), expected \(ruled)"
            }
            let current = try await client.current()
            guard current == model.live else {
                return "step \(number), \(step): current() is \(brief(Update(state: current))), "
                    + "expected \(brief(Update(state: model.live)))"
            }
            expected.early += [published].compactMap(\.self)
            expected.late += number >= joining ? [published].compactMap(\.self) : []
        }
        let mark = try await markEnd(of: client)
        let joined = await late?.updates(before: mark) ?? []
        return await ContractCheck.first(
            expectUpdates(early.updates(before: mark), expected.early),
            expectUpdates(joined, expected.late, "the updates of a stream opened at step \(joining)")
        )
    }
}

/// Writes a script call by call, following the model so that it knows whether a workout is live and which
/// rows it has.
private struct ScriptWriter {
    typealias Contract = WorkoutSessionClientContract

    var random: ScriptGenerator
    var model = Contract.Model()
    /// The device's clock, in seconds after the fixture start: each call is 1 to 120 s after the last.
    var seconds = 0.0
    var workouts = 0
    var addedSets = 0

    var now: Date {
        Contract.at(seconds)
    }

    mutating func next() -> Contract.Step {
        seconds += Double(Int.random(in: 1 ... 120, using: &random))
        let step = if let live = model.live {
            liveStep(live)
        } else {
            idleStep()
        }
        _ = model.perform(step)
        return step
    }

    /// With no workout: mostly a start, sometimes a call that must be refused.
    private mutating func idleStep() -> Contract.Step {
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0: .apply(.restSkipped)
        case 1: .apply(.started(snapshot()))
        case 2: .finish(endedAt: now)
        case 3: .discard(endedAt: now)
        case 4: .start(endedSnapshot())
        default: .start(snapshot())
        }
    }

    /// On a live workout: mostly set edits, then rests and a swap, events the engine ignores, a start that
    /// must be refused, and about one call in eight ends the workout.
    private mutating func liveStep(_ live: WorkoutState) -> Contract.Step {
        switch Int.random(in: 0 ..< 24, using: &random) {
        case 0 ..< 14: .apply(setEvent(live))
        case 14 ..< 18: .apply(restOrSwap(live))
        case 18 ..< 20: .apply(ignoredEvent(live))
        case 20: .start(Bool.random(using: &random) ? snapshot() : endedSnapshot())
        case 21: .finish(endedAt: now)
        case 22: .discard(endedAt: now)
        default: .apply(Bool.random(using: &random) ? .finished(endedAt: now) : .discarded(endedAt: now))
        }
    }

    /// The next workout's snapshot: the five solo exercises or the superset pair in turn, with auto rest on or
    /// off, started now.
    private mutating func snapshot() -> WorkoutState {
        workouts += 1
        return EventBuilders.session(
            workouts.isMultiple(of: 2) ? EventBuilders.supersetExercises : EventBuilders.seedExercises,
            id: WorkoutID(EventBuilders.uuid(0xF200 + workouts)),
            autoRest: Bool.random(using: &random),
            startedAt: now
        )
    }

    /// A snapshot `start` must refuse, live workout or not: the next workout's, already finished.
    private mutating func endedSnapshot() -> WorkoutState {
        var ended = snapshot()
        ended.phase = .finished
        ended.endedAt = now
        return ended
    }

    /// An edit of one row. The exercise and the row are drawn one past the last, so now and then the event
    /// names a row that is not there: the engine accepts it and changes nothing.
    private mutating func setEvent(_ live: WorkoutState) -> WorkoutEvent {
        let exercise = Int.random(in: 0 ... live.exercises.count, using: &random)
        let row = Int.random(in: 0 ... 5, using: &random)
        let setID = EventBuilders.setID(exercise, row, workout: live.id)
        let weight = Weight.pounds(Decimal(5 * Int.random(in: 0 ... 60, using: &random)))
        let reps = Reps(clamping: Int.random(in: 1 ... 15, using: &random))
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0 ..< 4:
            return .setLogged(exerciseIndex: exercise, setID: setID, weight: weight, reps: reps, doneAt: now)
        case 4:
            return .setUnlogged(exerciseIndex: exercise, setID: setID)
        case 5, 6:
            return .setTargetChanged(exerciseIndex: exercise, setID: setID, weight: weight, reps: nil)
        case 7:
            return .exerciseSelected(exerciseIndex: exercise, setIndex: row)
        case 8:
            return .allSetsRepeated(exerciseIndex: exercise, weight: weight, reps: reps)
        default:
            addedSets += 1
            let id = SetID(EventBuilders.uuid(0xA000 + addedSets))
            return .setAdded(exerciseIndex: exercise, set: LoggedSet(id: id, weight: weight, reps: reps, kind: .added))
        }
    }

    private mutating func restOrSwap(_ live: WorkoutState) -> WorkoutEvent {
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0:
            .restStarted(endsAt: now.addingTimeInterval(90), total: .seconds(90))
        case 1, 2:
            .restExtended(amount: .seconds(30), extendsShownRest: Bool.random(using: &random), tappedAt: now)
        case 3:
            .restSkipped
        default:
            .exerciseSwapped(
                exerciseIndex: Int.random(in: 0 ..< max(1, live.exercises.count), using: &random),
                exerciseID: ExerciseID(EventBuilders.uuid(0xE100 + Int.random(in: 0 ..< 4, using: &random))),
                name: "Replacement",
                alsoUpdateProgram: Bool.random(using: &random)
            )
        }
    }

    /// What ADR-004 has the engine ignore on a live workout: a second `started`, a rest that is too long, a
    /// date that is not finite.
    private mutating func ignoredEvent(_ live: WorkoutState) -> WorkoutEvent {
        switch Int.random(in: 0 ..< 4, using: &random) {
        case 0:
            .started(live)
        case 1:
            .restStarted(endsAt: now, total: WorkoutEngine.longestRest + .seconds(1))
        case 2:
            .finished(endedAt: Contract.never)
        default:
            .setLogged(
                exerciseIndex: 0,
                setID: EventBuilders.setID(0, 0, workout: live.id),
                weight: .zero,
                reps: .one,
                doneAt: Contract.never
            )
        }
    }
}

/// SplitMix64: a small generator whose sequence depends only on its seed.
private struct ScriptGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
