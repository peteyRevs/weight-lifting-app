import Foundation
import LedgerDomain
import LedgerTestSupport

/// An event for `Seam.session(1)` as started, what it is here for, and the haptics criterion 3 forwards
/// for it (none for an event the engine ignores).
struct SeamEventCase: Sendable, CustomStringConvertible {
    let description: String
    let event: WorkoutEvent
    let haptics: [Effect]

    init(_ description: String, _ event: WorkoutEvent, haptics: [Effect] = []) {
        self.description = description
        self.event = event
        self.haptics = haptics
    }
}

/// One event of every kind `apply` takes, in ADR-004's three classes.
enum SeamEvents {
    static let unknownSet = Seam.freshSet(900).id
    static let tooLong = WorkoutEngine.longestRest + Duration(attoseconds: 1)
    static let swapped = ExerciseID(EventBuilders.uuid(0xEE01))
    static let firstSet = Seam.setID(0, 0, in: 1)

    /// Events the engine applies: each changes the workout.
    static let changing: [SeamEventCase] = [
        SeamEventCase("a first log", Seam.logged(0, 0, in: 1), haptics: [.haptic(.setLogged)]),
        SeamEventCase("a log off the cursor", Seam.logged(3, 2, in: 1), haptics: [.haptic(.setLogged)]),
        SeamEventCase(
            "a stepper edit",
            .setTargetChanged(exerciseIndex: 1, setID: Seam.setID(1, 1, in: 1), weight: .pounds(60), reps: nil)
        ),
        SeamEventCase("an added set", .setAdded(exerciseIndex: 2, set: Seam.freshSet(1))),
        SeamEventCase("repeat last", .allSetsRepeated(exerciseIndex: 0, weight: .pounds(180), reps: .one)),
        SeamEventCase(
            "a swap",
            .exerciseSwapped(exerciseIndex: 0, exerciseID: swapped, name: "Dumbbell Bench", alsoUpdateProgram: true)
        ),
        SeamEventCase("a cursor move", .exerciseSelected(exerciseIndex: 4, setIndex: 1)),
        SeamEventCase("a rest", .restStarted(endsAt: Seam.at(150), total: .seconds(150))),
        SeamEventCase("a rest of exactly an hour", .restStarted(endsAt: Seam.at(9), total: WorkoutEngine.longestRest)),
        SeamEventCase(
            "+30s with no rest",
            .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: Seam.at(9))
        )
    ]

    /// Events the engine accepts and that leave the workout as it was: part of the log all the same, so
    /// published once (the protocol's `apply`, first bullet).
    static let unchanging: [SeamEventCase] = [
        SeamEventCase("skip with no rest", .restSkipped),
        SeamEventCase("an un-log of a set that is not done", .setUnlogged(exerciseIndex: 0, setID: firstSet)),
        SeamEventCase(
            "a stepper edit of nothing",
            .setTargetChanged(exerciseIndex: 0, setID: firstSet, weight: nil, reps: nil)
        ),
        SeamEventCase("a cursor move onto the cursor", .exerciseSelected(exerciseIndex: 0, setIndex: 0)),
        SeamEventCase("a cursor move to no row", .exerciseSelected(exerciseIndex: 9, setIndex: -1)),
        SeamEventCase("a log of a set that is not there", log(0, unknownSet, doneAt: Seam.at(5))),
        SeamEventCase("a log in an exercise that is not there", log(-1, firstSet, doneAt: Seam.at(5))),
        SeamEventCase(
            "a swap of an exercise that is not there",
            .exerciseSwapped(exerciseIndex: 5, exerciseID: swapped, name: "Nothing", alsoUpdateProgram: false)
        ),
        SeamEventCase("an added set the workout already holds", .setAdded(exerciseIndex: 3, set: heldSet))
    ]

    /// What ADR-004 has the engine ignore on a live workout: no state change, no effects.
    static let ignored: [SeamEventCase] = [
        SeamEventCase("a second started, same snapshot", .started(Seam.session(1))),
        SeamEventCase("a second started, another workout", .started(Seam.session(2, EventBuilders.supersetExercises))),
        SeamEventCase("a log done at +infinity", log(0, firstSet, doneAt: Seam.infinity)),
        SeamEventCase("a log done at -infinity", log(0, firstSet, doneAt: Seam.minusInfinity)),
        SeamEventCase("a log done at NaN", log(0, firstSet, doneAt: Seam.notANumber)),
        SeamEventCase("an added set done at NaN", .setAdded(exerciseIndex: 0, set: doneNever)),
        SeamEventCase("a rest ending at +infinity", .restStarted(endsAt: Seam.infinity, total: .seconds(60))),
        SeamEventCase("a rest an attosecond over an hour", .restStarted(endsAt: Seam.at(60), total: tooLong)),
        SeamEventCase(
            "a rest of minus an attosecond",
            .restStarted(endsAt: Seam.at(60), total: Duration(attoseconds: -1))
        ),
        SeamEventCase(
            "+30s tapped at NaN",
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Seam.notANumber)
        ),
        SeamEventCase(
            "an extension over an hour",
            .restExtended(amount: tooLong, extendsShownRest: false, tappedAt: Seam.at(5))
        ),
        SeamEventCase(
            "a negative extension",
            .restExtended(amount: .seconds(-30), extendsShownRest: true, tappedAt: Seam.at(5))
        ),
        SeamEventCase("finished at +infinity", .finished(endedAt: Seam.infinity)),
        SeamEventCase("discarded at NaN", .discarded(endedAt: Seam.notANumber))
    ]

    static func log(_ exerciseIndex: Int, _ setID: SetID, doneAt: Date) -> WorkoutEvent {
        .setLogged(exerciseIndex: exerciseIndex, setID: setID, weight: .pounds(45), reps: .one, doneAt: doneAt)
    }

    /// A set `Seam.session(1)` holds, offered again by "+ Add set" (rule 6: once per set id).
    static var heldSet: LoggedSet {
        LoggedSet(id: firstSet, weight: .pounds(999), reps: .one, kind: .added)
    }

    static var doneNever: LoggedSet {
        var set = Seam.freshSet(2)
        set.doneAt = Seam.notANumber
        return set
    }
}
