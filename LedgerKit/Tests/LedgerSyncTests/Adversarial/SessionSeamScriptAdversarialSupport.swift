import Foundation
import LedgerDomain
import LedgerTestSupport

/// Writes a seeded script call by call, told the live workout before each: legal calls (starts, set edits,
/// rests, swaps, ends) and the ones a client must refuse or ignore (a start on a live workout, an ended or
/// malformed snapshot, a call with nothing live, rows and sets that do not exist, dates that are not finite,
/// rests outside `0 ... WorkoutEngine.longestRest`, a second `started`).
struct SeamScriptWriter {
    var random: SeamRandom
    /// The device's clock, in seconds after the fixture start.
    private var seconds = 0.0
    private var workouts = 0
    private var freshSets = 0

    init(seed: UInt64) {
        random = SeamRandom(seed: seed)
    }

    mutating func next(live: WorkoutState?) -> SeamCall {
        seconds += Double(Int.random(in: 1 ... 90, using: &random))
        guard let live else {
            return idleCall()
        }
        switch Int.random(in: 0 ..< 40, using: &random) {
        case 0 ..< 18: return .apply(setEvent(live))
        case 18 ..< 24: return .apply(restEvent())
        case 24 ..< 28: return .apply(otherEvent(live))
        case 28 ..< 32: return .apply(ignoredEvent(live))
        case 32 ..< 35: return .start(Bool.random(using: &random) ? snapshot(reusing: live.id) : spoiledSnapshot())
        default: return endingCall(live)
        }
    }

    /// The calls that end a workout, by either route, and a cursor move.
    private mutating func endingCall(_ live: WorkoutState) -> SeamCall {
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0: .finish(endDate())
        case 1: .discard(endDate())
        case 2: .apply(.finished(endedAt: endDate()))
        case 3: .apply(.discarded(endedAt: endDate()))
        default: .apply(.exerciseSelected(exerciseIndex: index(live.exercises.count), setIndex: index(6)))
        }
    }

    /// With no workout: mostly a start, sometimes a call that must be refused.
    private mutating func idleCall() -> SeamCall {
        switch Int.random(in: 0 ..< 12, using: &random) {
        case 0: .apply(.restSkipped)
        case 1: .apply(.started(snapshot(reusing: nil)))
        case 2: .finish(endDate())
        case 3: .discard(endDate())
        case 4, 5: .start(spoiledSnapshot())
        case 6: .apply(.finished(endedAt: now))
        default: .start(snapshot(reusing: nil))
        }
    }

    private var now: Date {
        Seam.at(seconds)
    }

    /// An index into `count` rows, now and then one outside them.
    private mutating func index(_ count: Int) -> Int {
        Int.random(in: -1 ... count, using: &random)
    }

    /// The device's clock, or one time in four a date that is not finite.
    private mutating func endDate() -> Date {
        Int.random(in: 0 ..< 4, using: &random) == 0 ? Seam.nonFinite[Int.random(in: 0 ..< 3, using: &random)] : now
    }

    private mutating func weight() -> Weight {
        let pounds: [Decimal] = [-45, 0, 2.5, 45, 185, 0.125, 1_000_000]
        return .pounds(pounds[Int.random(in: 0 ..< pounds.count, using: &random)])
    }

    private mutating func reps() -> Reps {
        Reps(clamping: Int.random(in: -2 ... 30, using: &random))
    }

    /// A live snapshot: the five solo exercises, the superset pair, a drop-set exercise or none at all,
    /// sometimes mid-rest, with a set already done, or with a cursor that points nowhere. One time in
    /// five, when asked, under the id of the workout that is live.
    private mutating func snapshot(reusing liveID: WorkoutID?) -> WorkoutState {
        workouts += 1
        let drop = [EventBuilders.ExerciseSpec(
            "Leg Press",
            .machine,
            sets: 2,
            reps: 12,
            pounds: 300,
            restSeconds: 120,
            dropSet: true
        )]
        let shapes = [EventBuilders.seedExercises, EventBuilders.supersetExercises, drop, []]
        var session = Seam.session(workouts, shapes[workouts % shapes.count], autoRest: Bool.random(using: &random))
        if let liveID, Int.random(in: 0 ..< 5, using: &random) == 0 {
            session = EventBuilders.session(shapes[workouts % shapes.count], id: liveID)
        }
        session.startedAt = now
        switch Int.random(in: 0 ..< 6, using: &random) {
        case 0: session.rest = RestTimer(endsAt: now.addingTimeInterval(90), total: .seconds(90))
        case 1: session.cursor = Cursor(exerciseIndex: 40, setIndex: -3)
        case 2: session.cursor = nil
        case 3 where !session.exercises.isEmpty: session.exercises[0].sets[0].doneAt = now
        default: break
        }
        return session
    }

    /// A snapshot `start` must refuse, live workout or not: ended, or holding a date that is not finite or
    /// a rest outside the engine's bounds (`EventEnvelope.isWellFormed`).
    private mutating func spoiledSnapshot() -> WorkoutState {
        var session = snapshot(reusing: nil)
        let never = Seam.nonFinite[Int.random(in: 0 ..< 3, using: &random)]
        switch Int.random(in: 0 ..< 7, using: &random) {
        case 0: session.phase = .finished
        case 1: session.phase = .discarded
        case 2: session.startedAt = never
        case 3: session.endedAt = never
        case 4: session.rest = RestTimer(endsAt: never, total: .seconds(60))
        case 5: session.rest = RestTimer(endsAt: now, total: WorkoutEngine.longestRest + .nanoseconds(1))
        default: session.rest = RestTimer(endsAt: now, total: .seconds(-1))
        }
        return session
    }
}

/// The events a script applies to a live workout.
private extension SeamScriptWriter {
    /// An edit of one row. The exercise is drawn one outside the list on each side, and the set is now and
    /// then one the workout does not hold: the engine accepts the event and changes nothing.
    mutating func setEvent(_ live: WorkoutState) -> WorkoutEvent {
        let exerciseIndex = index(live.exercises.count)
        let sets = live.exercises.indices.contains(exerciseIndex) ? live.exercises[exerciseIndex].sets : []
        freshSets += 1
        let unknown = Seam.freshSet(freshSets)
        let known = sets.isEmpty ? unknown : sets[Int.random(in: 0 ..< sets.count, using: &random)]
        let setID = Int.random(in: 0 ..< 8, using: &random) == 0 ? unknown.id : known.id
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0 ..< 4:
            return .setLogged(exerciseIndex: exerciseIndex, setID: setID, weight: weight(), reps: reps(), doneAt: now)
        case 4:
            return .setUnlogged(exerciseIndex: exerciseIndex, setID: setID)
        case 5:
            return .setTargetChanged(exerciseIndex: exerciseIndex, setID: setID, weight: weight(), reps: nil)
        case 6:
            return .setTargetChanged(exerciseIndex: exerciseIndex, setID: setID, weight: nil, reps: reps())
        case 7:
            return .setAdded(exerciseIndex: exerciseIndex, set: Bool.random(using: &random) ? unknown : known)
        case 8:
            return .allSetsRepeated(exerciseIndex: exerciseIndex, weight: weight(), reps: reps())
        default:
            return .setLogged(
                exerciseIndex: exerciseIndex,
                setID: setID,
                weight: weight(),
                reps: reps(),
                doneAt: .distantPast
            )
        }
    }

    /// Rule 9's events, inside the engine's bounds (zero and exactly `longestRest` included).
    mutating func restEvent() -> WorkoutEvent {
        let lengths: [Duration] = [.zero, .seconds(30), .seconds(90), WorkoutEngine.longestRest]
        let length = lengths[Int.random(in: 0 ..< lengths.count, using: &random)]
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0: return .restStarted(endsAt: now.addingTimeInterval(length / .seconds(1)), total: length)
        case 1: return .restStarted(endsAt: .distantFuture, total: length)
        case 2: return .restExtended(amount: length, extendsShownRest: true, tappedAt: now)
        case 3: return .restExtended(amount: length, extendsShownRest: false, tappedAt: now)
        default: return .restSkipped
        }
    }

    mutating func otherEvent(_ live: WorkoutState) -> WorkoutEvent {
        let exerciseIndex = index(live.exercises.count)
        workouts += 1
        return .exerciseSwapped(
            exerciseIndex: exerciseIndex,
            exerciseID: ExerciseID(EventBuilders.uuid(0xEE0000 + workouts)),
            name: "Swap \(workouts)",
            alsoUpdateProgram: Bool.random(using: &random)
        )
    }

    /// What ADR-004 has the engine ignore on a live workout: a second `started`, a date that is not finite,
    /// a rest outside its bounds.
    mutating func ignoredEvent(_ live: WorkoutState) -> WorkoutEvent {
        let never = Seam.nonFinite[Int.random(in: 0 ..< 3, using: &random)]
        let tooLong = WorkoutEngine.longestRest + .nanoseconds(1)
        var done = Seam.freshSet(0)
        done.doneAt = never
        switch Int.random(in: 0 ..< 8, using: &random) {
        case 0: return .started(snapshot(reusing: live.id))
        case 1: return .started(live)
        case 2: return .restStarted(endsAt: now, total: tooLong)
        case 3: return .restStarted(endsAt: never, total: .seconds(60))
        case 4: return .restExtended(amount: .seconds(-30), extendsShownRest: true, tappedAt: now)
        case 5: return .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: never)
        case 6: return .setAdded(exerciseIndex: 0, set: done)
        default:
            let setID = live.exercises.first?.sets.first?.id ?? done.id
            return .setLogged(exerciseIndex: 0, setID: setID, weight: .pounds(45), reps: .one, doneAt: never)
        }
    }
}
