import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rule 20's four branches at their edges, drop rows, and auto-rest off.
@Suite("WorkoutEngine · cursor edges (adversarial)", .tags(.domain))
struct CursorEdgeAdversarialTests {
    typealias Adv = EngineAdv

    static func log(
        _ state: WorkoutState?,
        _ exercise: Int,
        _ set: Int,
        at seconds: Double,
        seq: UInt64
    ) -> WorkoutState? {
        SetLoggedCursorAdversarialTests.log(state, exercise, set, at: seconds, seq: seq).state
    }

    static func select(_ state: WorkoutState?, _ exercise: Int, _ set: Int, seq: UInt64) -> WorkoutState? {
        WorkoutEngine.reduce(
            state, Adv.env(.exerciseSelected(exerciseIndex: exercise, setIndex: set), seq: seq, at: Double(seq))
        ).0
    }

    @Test("Rule 20 branch 2: nothing undone later in the block → the earliest undone row earlier.")
    func wrapsToEarliestUndone() {
        var state = Adv.state(after: [Adv.start()])
        state = Self.select(state, 0, 2, seq: 2)
        state = Self.log(state, 0, 2, at: 10, seq: 3)
        #expect(state?.cursor == Adv.cursor(0, 3))
        state = Self.log(state, 0, 3, at: 20, seq: 4)
        state = Self.log(state, 0, 4, at: 30, seq: 5)
        #expect(state?.cursor == Adv.cursor(0, 0))
    }

    @Test("Rule 20 branch 3: block complete → the first set of the next block, even if that set is already done.")
    func nextBlockFirstSet_evenWhenDone() {
        var state = Adv.state(after: [Adv.start()])
        state = Self.select(state, 1, 0, seq: 2)
        state = Self.log(state, 1, 0, at: 10, seq: 3)
        for set in 0 ..< 5 {
            state = Self.log(state, 0, set, at: Double(20 + set), seq: UInt64(4 + set))
        }
        // Spec §7.4 rule 20 / prototype nextOf: `nb ? { ei: nb[0], si: 0 }` — no done check.
        #expect(state?.cursor == Adv.cursor(1, 0))
    }

    @Test("Rule 20 branch 4: last block complete → the cursor stays where it was, not on the logged row.")
    func lastBlockComplete_cursorStays() {
        let specs = [Adv.spec("A", sets: 2, rest: 60), Adv.spec("B", sets: 1, rest: 60)]
        var state = Adv.state(after: [Adv.start(EventBuilders.session(specs))])
        state = Self.log(state, 1, 0, at: 10, seq: 2)
        #expect(state?.cursor == Adv.cursor(0, 0))
    }

    @Test("Rule 20: a straight exercise's drop row is next after its last working row, and it rests too.")
    func dropRow_followsWorkingRows() {
        let specs = [Adv.spec("A", sets: 2, rest: 60, drop: true), Adv.spec("B", sets: 1, rest: 30)]
        var state = Adv.state(after: [Adv.start(EventBuilders.session(specs))])
        state = Self.log(state, 0, 0, at: 10, seq: 2)
        state = Self.log(state, 0, 1, at: 20, seq: 3)
        #expect(state?.cursor == Adv.cursor(0, 2))
        state = Self.log(state, 0, 2, at: 30, seq: 4)
        #expect(state?.rest == RestTimer(endsAt: engineTime(90), total: .seconds(60)))
        #expect(state?.cursor == Adv.cursor(1, 0))
    }

    @Test("Rule 20: superset drop rows form their own last round — AD does not rest, BD does.")
    func supersetDropRound() {
        let specs = [
            Adv.spec("A", sets: 2, rest: 90, drop: true), Adv.spec("B", sets: 2, rest: 60, superset: true, drop: true)
        ]
        var state = Adv.state(after: [Adv.start(EventBuilders.session(specs))])
        let order = [(0, 0), (1, 0), (0, 1), (1, 1)]
        for (step, row) in order.enumerated() {
            state = Self.log(state, row.0, row.1, at: Double(10 * (step + 1)), seq: UInt64(step + 2))
        }
        #expect(state?.cursor == Adv.cursor(0, 2))
        state = Self.log(state, 0, 2, at: 50, seq: 6)
        #expect(state?.rest?.endsAt == engineTime(130), "AD is not the last of the drop round")
        #expect(state?.cursor == Adv.cursor(1, 2))
        state = Self.log(state, 1, 2, at: 60, seq: 7)
        #expect(state?.rest == RestTimer(endsAt: engineTime(150), total: .seconds(90)))
    }

    @Test("Rules 20 + 26: an added set (appended after the drop row) is a working-round row, before the drop row.")
    func addedAfterDrop_comesBeforeDropInOrder() {
        let specs = [Adv.spec("A", sets: 2, rest: 60, drop: true)]
        let added = LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: pounds("50"), reps: Reps.one, kind: .added)
        var state = Adv.state(after: [
            Adv.start(EventBuilders.session(specs)),
            Adv.env(.setAdded(exerciseIndex: 0, set: added), Adv.watch, seq: 1, at: 1)
        ])
        #expect(state?.exercises[0].sets.map(\.kind) == [.working, .working, .drop, .added])
        state = Self.log(state, 0, 0, at: 10, seq: 2)
        state = Self.log(state, 0, 1, at: 20, seq: 3)
        #expect(state?.cursor == Adv.cursor(0, 3))
    }

    @Test("Decision #7: with auto-rest off no rest starts and no notification is scheduled; the cursor still moves.")
    func autoRestOff_noRest() {
        let started = Adv.state(after: [Adv.start(EventBuilders.seedSession(autoRest: false))])
        let (state, effects) = WorkoutEngine.reduce(started, Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10))
        #expect(state?.rest == nil)
        #expect(state?.cursor == Adv.cursor(0, 1))
        #expect(!Adv.schedulesRest(effects))
    }

    @Test("Bounds: a next block whose first member has no rows never leaves the cursor on a missing row.")
    func nextBlockWithEmptyFirstMember_cursorIsARealRow() throws {
        let specs = [
            Adv.spec("A", sets: 1, rest: 60), Adv.spec("B", sets: 0, rest: 60),
            Adv.spec("C", sets: 2, rest: 60, superset: true)
        ]
        let state = try #require(Self.log(
            Adv.state(after: [Adv.start(EventBuilders.session(specs))]),
            0,
            0,
            at: 10,
            seq: 2
        ))
        let cursor = try #require(state.cursor)
        #expect(Adv.row(state, cursor.exerciseIndex, cursor.setIndex) != nil, "cursor \(cursor) points at no row")
        #expect(cursor == Adv.cursor(2, 0), "the next block's display order starts at C1")
    }

    @Test("Bounds: an empty next block never leaves the cursor on a missing row.")
    func emptyNextBlock_cursorIsARealRow() throws {
        let specs = [
            Adv.spec("A", sets: 1, rest: 60),
            Adv.spec("B", sets: 0, rest: 60),
            Adv.spec("C", sets: 1, rest: 60)
        ]
        let state = try #require(Self.log(
            Adv.state(after: [Adv.start(EventBuilders.session(specs))]),
            0,
            0,
            at: 10,
            seq: 2
        ))
        let cursor = try #require(state.cursor)
        #expect(Adv.row(state, cursor.exerciseIndex, cursor.setIndex) != nil, "cursor \(cursor) points at no row")
    }
}
