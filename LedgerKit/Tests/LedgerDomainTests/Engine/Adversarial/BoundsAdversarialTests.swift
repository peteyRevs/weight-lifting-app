import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rule 11 and the bounds of every index- or ID-addressed event: out-of-range exercise and set
/// indices, unknown set IDs and IDs addressed to the wrong exercise change nothing and never trap.
@Suite("WorkoutEngine · bounds (adversarial)", .tags(.domain))
struct BoundsAdversarialTests {
    typealias Adv = EngineAdv

    static let badIndices = [-1, 5, Int.max, Int.min, Int.max - 1]

    /// Every index-addressed event pointed at `exercise` with `setID`.
    static func addressed(_ exercise: Int, _ setID: SetID) -> [WorkoutEvent] {
        let added = LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: pounds("45"), reps: Reps.one, kind: .added)
        return [
            .exerciseSelected(exerciseIndex: exercise, setIndex: 0),
            .setLogged(
                exerciseIndex: exercise,
                setID: setID,
                weight: pounds("100"),
                reps: Reps.one,
                doneAt: engineTime(9)
            ),
            .setUnlogged(exerciseIndex: exercise, setID: setID),
            .setTargetChanged(exerciseIndex: exercise, setID: setID, weight: pounds("100"), reps: Reps.one),
            .setAdded(exerciseIndex: exercise, set: added),
            .allSetsRepeated(exerciseIndex: exercise, weight: pounds("100"), reps: Reps.one),
            .exerciseSwapped(
                exerciseIndex: exercise,
                exerciseID: ExerciseID(EventBuilders.uuid(0xA1)),
                name: "X",
                alsoUpdateProgram: true
            )
        ]
    }

    /// A live seed session with set (0, 0) done, so un-log has something to find.
    static func live() -> WorkoutState? {
        Adv.state(after: [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 1), seq: 2, at: 1)])
    }

    @Test(
        "Bounds: every index-addressed event with an out-of-range exercise index changes nothing.",
        arguments: badIndices
    )
    func outOfRangeExercise_changesNothing(index: Int) {
        let live = Self.live()
        for event in Self.addressed(index, Adv.sid(0, 1)) {
            let (state, effects) = WorkoutEngine.reduce(live, Adv.env(event, Adv.watch, seq: 1, at: 10))
            #expect(state == live, "\(event)")
            #expect(!effects.contains(.updateLiveActivity), "\(event) claimed a change: \(effects)")
            #expect(!Adv.buzzes(effects), "\(event): \(effects)")
        }
    }

    @Test("Bounds: set events with an unknown set ID, or a real ID sent to the wrong exercise, change nothing.")
    func unknownOrMisaddressedSetID_changesNothing() {
        let live = Self.live()
        let cases: [(Int, SetID)] = [(0, SetID(EventBuilders.uuid(0xDEAD))), (1, Adv.sid(0, 1)), (1, Adv.sid(0, 0))]
        for (exercise, setID) in cases {
            let events = Self.addressed(exercise, setID).filter {
                switch $0 {
                case .setLogged, .setUnlogged, .setTargetChanged: true
                default: false
                }
            }
            for event in events {
                let (state, effects) = WorkoutEngine.reduce(live, Adv.env(event, Adv.watch, seq: 1, at: 10))
                #expect(state == live, "\(event)")
                #expect(!effects.contains(.haptic(.setLogged)), "\(event): \(effects)")
                #expect(
                    !Adv.schedulesRest(effects),
                    "\(event)"
                )
            }
        }
    }

    @Test("Rule 11: selecting an existing undone row moves the cursor there.")
    func select_undoneRow() {
        let (state, _) = WorkoutEngine.reduce(
            Self.live(), Adv.env(.exerciseSelected(exerciseIndex: 3, setIndex: 2), Adv.watch, seq: 1, at: 10)
        )
        #expect(state?.cursor == Adv.cursor(3, 2))
    }

    @Test(
        "Rule 11: selecting a done row or a row that does not exist is ignored.",
        arguments: [(0, 0), (0, 5), (0, -1), (-1, 0), (5, 0), (Int.max, Int.max), (Int.min, Int.min), (4, Int.max)]
    )
    func select_doneOrMissingRow_isIgnored(row: (Int, Int)) {
        let live = Self.live()
        let (state, effects) = WorkoutEngine.reduce(
            live, Adv.env(.exerciseSelected(exerciseIndex: row.0, setIndex: row.1), Adv.watch, seq: 1, at: 10)
        )
        #expect(state == live)
        #expect(!effects.contains(.updateLiveActivity))
    }

    @Test("Bounds: a session with no exercises (cursor nil) accepts every event without trapping.")
    func emptySession_acceptsEverything() throws {
        let empty = EventBuilders.session([])
        var state = Adv.state(after: [Adv.start(empty)])
        #expect(state?.cursor == nil)
        let events = Self.addressed(0, Adv.sid(0, 0)) + [Adv.extend(shown: true, tappedAt: 1), .restSkipped]
        for (offset, event) in events.enumerated() {
            state = WorkoutEngine.reduce(state, Adv.env(event, seq: UInt64(offset + 2), at: Double(offset + 1))).0
        }
        let final = try #require(state)
        #expect(final.exercises.isEmpty)
        #expect(final.cursor == nil)
    }

    @Test("Bounds: a snapshot whose cursor points nowhere does not trap the reducer.")
    func snapshotWithBadCursor_doesNotTrap() {
        var snapshot = EventBuilders.seedSession()
        snapshot.cursor = Adv.cursor(99, -3)
        let state = Adv.state(after: [
            Adv.start(snapshot),
            Adv.env(Adv.logged(0, 0, doneAt: 1), seq: 2, at: 1),
            Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), seq: 3, at: 2)
        ])
        #expect(Adv.row(state, 0, 0)?.isDone == false)
        #expect(state?.cursor == Adv.cursor(0, 1))
    }
}
