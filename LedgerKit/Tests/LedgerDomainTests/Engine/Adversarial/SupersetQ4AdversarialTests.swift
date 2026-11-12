import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S9 (criteria 1–3, ruling Q4 as built): the public rounds and the rule that a not-done → done row that
/// is not the last of its round ends the rest, attacked with 2- and 3-member blocks of unequal counts, added sets
/// that move the last row of a round, drop rounds, un-logs in the middle of a round, re-logs, auto rest off, and
/// seeded scripts of every edit against `ModelOracle`.
@Suite("SupersetRounds and Q4 (adversarial, F10 S9)", .tags(.domain))
struct SupersetQ4AdversarialTests {
    typealias SetRef = SupersetRounds.SetRef

    /// A (3 sets, 90 s), B (1 set, 60 s), C (2 sets, 120 s): one block of three of unequal counts.
    static let three = EventBuilders.session([
        .init("A", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
        .init("B", .machine, sets: 1, reps: 8, pounds: 70, restSeconds: 60, superset: true),
        .init("C", .cable, sets: 2, reps: 12, pounds: 20, restSeconds: 120, superset: true)
    ])

    /// A (3) and B (2, with a drop set): B drops out of round 3; AD is absent, BD is the drop round.
    static let pairWithDrop = EventBuilders.session([
        .init("A", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90, dropSet: true),
        .init("B", .machine, sets: 2, reps: 8, pounds: 70, restSeconds: 60, superset: true, dropSet: true)
    ])

    static func ref(_ exercise: Int, _ set: Int) -> SetRef {
        SetRef(exerciseIndex: exercise, setIndex: set)
    }

    static func own(_ effects: [Effect]) -> [Effect] {
        effects.filter {
            switch $0 {
            case .persist, .transmit, .updateLiveActivity: false
            default: true
            }
        }
    }

    // MARK: Rounds

    @Test("Three members of 3, 1 and 2 sets: rounds [A1 B1 C1] [A2 C2] [A3]; round(of:) of each; out of range nil")
    func rounds_threeMembersUnequal() throws {
        let block = try #require(SupersetRounds.blocks(in: Self.three.exercises).first)
        let rounds = SupersetRounds.rounds(block: block, exercises: Self.three.exercises)
        let expected = [
            [Self.ref(0, 0), Self.ref(1, 0), Self.ref(2, 0)], [Self.ref(0, 1), Self.ref(2, 1)], [Self.ref(0, 2)]
        ]
        let same = rounds == expected
        #expect(same)
        let roundsOf = [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2)].map {
            SupersetRounds.round(of: Self.ref($0.0, $0.1), block: block, exercises: Self.three.exercises)
        }
        #expect(roundsOf == [0, 0, 0, 1, 1, 2])
        #expect(SupersetRounds.round(of: Self.ref(1, 1), block: block, exercises: Self.three.exercises) == nil)
        #expect(SupersetRounds.round(of: Self.ref(7, 0), block: block, exercises: Self.three.exercises) == nil)
        // The last of each round: C1, C2, A3.
        let lasts = [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2)].filter {
            SupersetRounds.isLastOfRound(Self.ref($0.0, $0.1), block: block, exercises: Self.three.exercises)
        }
        #expect(lasts.map { [$0.0, $0.1] } == [[2, 0], [2, 1], [0, 2]])
    }

    @Test("Drop rows form the final round(s): A1 B1 A2 B2 A3, then AD BD")
    func rounds_dropRowsLast() throws {
        let block = try #require(SupersetRounds.blocks(in: Self.pairWithDrop.exercises).first)
        let rounds = SupersetRounds.rounds(block: block, exercises: Self.pairWithDrop.exercises)
        let expected = [
            [Self.ref(0, 0), Self.ref(1, 0)], [Self.ref(0, 1), Self.ref(1, 1)], [Self.ref(0, 2)],
            [Self.ref(0, 3), Self.ref(1, 2)]
        ]
        let same = rounds == expected
        #expect(same)
    }

    // MARK: Q4 in a block of three

    @Test("Q4, three members: C1 starts the 120 s group rest; A2 ends it; C2 starts it; A3 (alone) starts it")
    func q4_threeMembers_walk() throws {
        var state = try #require(WorkoutEngine.reduce(nil, Engine.started(Self.three)).0)
        var seq: UInt64 = 2
        func log(_ exercise: Int, _ set: Int, at seconds: Double) -> [Effect] {
            let envelope = Engine.envelope(Engine.logged(exercise, set, at: seconds), seconds, seq: seq)
            seq += 1
            let (next, effects) = WorkoutEngine.reduce(state, envelope)
            state = next ?? state
            return Self.own(effects)
        }
        #expect(log(0, 0, at: 10) == [.haptic(.setLogged)])
        #expect(log(1, 0, at: 20) == [.haptic(.setLogged)])
        #expect(log(2, 0, at: 30) == [.haptic(.setLogged), .scheduleRestNotification(endsAt: Engine.at(150))])
        #expect(state.rest == RestTimer(endsAt: Engine.at(150), total: .seconds(120)))
        #expect(state.cursor == Cursor(exerciseIndex: 0, setIndex: 1))
        #expect(log(0, 1, at: 60) == [.haptic(.setLogged), .cancelRestNotification])
        #expect(state.rest == nil)
        #expect(state.cursor == Cursor(exerciseIndex: 2, setIndex: 1), "B has no second set: C2 is next")
        #expect(log(2, 1, at: 70) == [.haptic(.setLogged), .scheduleRestNotification(endsAt: Engine.at(190))])
        #expect(log(0, 2, at: 200) == [.haptic(.setLogged), .scheduleRestNotification(endsAt: Engine.at(320))])
    }

    @Test("Q4 with an added set: B gets a third row, so A3 no longer ends its round and ends the rest instead")
    func q4_addedSetMovesTheLastOfRound() throws {
        let pair = EventBuilders.session([
            .init("A", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
            .init("B", .machine, sets: 2, reps: 8, pounds: 70, restSeconds: 60, superset: true)
        ])
        let firstFour = [
            Engine.logged(0, 0, at: 10),
            Engine.logged(1, 0, at: 20),
            Engine.logged(0, 1, at: 30),
            Engine.logged(1, 1, at: 40)
        ]
        // Without the added set A3 ends round 3: it starts a rest.
        let plain = try Engine.run(firstFour + [Engine.logged(0, 2, at: 200)], on: pair)
        #expect(plain.state.rest == RestTimer(endsAt: Engine.at(290), total: .seconds(90)))
        // With B3 added, A3 is not the last of its round: it ends B2's rest.
        let added = WorkoutEvent.setAdded(exerciseIndex: 1, set: LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(70), reps: Reps(clamping: 8), kind: .added
        ))
        let moved = try Engine.run(firstFour + [added, Engine.logged(0, 2, at: 60)], on: pair)
        #expect(moved.state.rest == nil)
        #expect(Self.own(moved.effects) == [.haptic(.setLogged), .cancelRestNotification])
        #expect(moved.state.cursor == Cursor(exerciseIndex: 1, setIndex: 2))
    }

    @Test("Q4, drop round: AD ends the rest of A3's round; BD starts the group rest")
    func q4_dropRound() throws {
        let working = [
            Engine.logged(0, 0, at: 10),
            Engine.logged(1, 0, at: 20),
            Engine.logged(0, 1, at: 30),
            Engine.logged(1, 1, at: 40),
            Engine.logged(0, 2, at: 50)
        ]
        let afterA3 = try Engine.run(working, on: Self.pairWithDrop)
        #expect(afterA3.state.rest == RestTimer(endsAt: Engine.at(140), total: .seconds(90)), "A3 is alone in round 3")
        #expect(afterA3.state.cursor == Cursor(exerciseIndex: 0, setIndex: 3), "AD is next")
        let atAD = try Engine.run(working + [Engine.logged(0, 3, at: 60)], on: Self.pairWithDrop)
        #expect(atAD.state.rest == nil)
        #expect(Self.own(atAD.effects) == [.haptic(.setLogged), .cancelRestNotification])
        let atBD = try Engine.run(
            working + [Engine.logged(0, 3, at: 60), Engine.logged(1, 2, at: 70)], on: Self.pairWithDrop
        )
        #expect(atBD.state.rest == RestTimer(endsAt: Engine.at(160), total: .seconds(90)))
    }
}

// MARK: - Un-logs, re-logs, auto rest off and a rest from another block

extension SupersetQ4AdversarialTests {
    // MARK: Q4, un-logs and re-logs

    @Test("Q4: un-logging B1 mid-rest keeps the rest (rule 22); its re-log starts the rest again")
    func q4_unlogTheRoundsLast_thenRelog() throws {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let round = [Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 20)]
        let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 1, setID: Engine.set(1, 0))
        let unlogged = try Engine.run(round + [unlog], on: session)
        #expect(unlogged.state.rest == RestTimer(endsAt: Engine.at(110), total: .seconds(90)))
        #expect(Self.own(unlogged.effects).isEmpty)
        let relogged = try Engine.run(round + [unlog, Engine.logged(1, 0, at: 40)], on: session)
        #expect(relogged.state.rest == RestTimer(endsAt: Engine.at(130), total: .seconds(90)))
    }

    @Test("Q4 refined: un-logging A1 and logging it again completes round 1, so B1's rest runs on")
    func q4_unlogAndRelogOfANonLastRow_keepsTheRest() throws {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let round = [Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 20)]
        let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0))
        let result = try Engine.run(round + [unlog, Engine.logged(0, 0, pounds: 60, at: 40)], on: session)
        // F10 S9 fix round 2 (sanctioned edit, Q4 refined): the re-logged A1 completes round 1, so B1's rest
        // runs on and nothing is cancelled.
        #expect(result.state.rest == RestTimer(endsAt: Engine.at(110), total: .seconds(90)))
        #expect(Self.own(result.effects) == [.haptic(.setLogged)])
    }

    @Test("Q4: a done → done re-log of A1 during the rest keeps it, whatever its values")
    func q4_relogDoneToDone_keepsTheRest() throws {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let result = try Engine.run(
            [Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 20), Engine.logged(0, 0, pounds: 80, at: 30)],
            on: session
        )
        #expect(result.state.rest == RestTimer(endsAt: Engine.at(110), total: .seconds(90)))
        #expect(Self.own(result.effects) == [.haptic(.setLogged)])
    }

    // MARK: Q4 and auto rest off, and a rest from another block

    @Test("Q4, auto rest off: A1 ends a manual rest; B1 (ends its round) leaves one alone, as a solo set does")
    func q4_autoRestOff() throws {
        let off = EventBuilders.session(EventBuilders.supersetExercises, autoRest: false)
        let atA1 = try Engine.run([Engine.extend(tapped: 5), Engine.logged(0, 0, at: 20)], on: off)
        #expect(atA1.state.rest == nil)
        #expect(Self.own(atA1.effects) == [.haptic(.setLogged), .cancelRestNotification])
        let atB1 = try Engine.run(
            [Engine.logged(0, 0, at: 10), Engine.extend(tapped: 15), Engine.logged(1, 0, at: 30)], on: off
        )
        #expect(atB1.state.rest == RestTimer(endsAt: Engine.at(45), total: .seconds(30)))
        #expect(Self.own(atB1.effects) == [.haptic(.setLogged)])
    }

    @Test("Q4 as ruled: the rest a solo exercise started ends at the first member of the next block")
    func q4_restFromASoloExercise_endsAtTheBlocksFirstRow() throws {
        let session = EventBuilders.session([
            .init("Bench", .barbell, sets: 1, reps: 5, pounds: 185, restSeconds: 150),
            .init("A", .dumbbell, sets: 2, reps: 10, pounds: 55, restSeconds: 90),
            .init("B", .machine, sets: 2, reps: 8, pounds: 70, restSeconds: 60, superset: true)
        ])
        let bench = try Engine.run([Engine.logged(0, 0, at: 10)], on: session)
        #expect(bench.state.rest == RestTimer(endsAt: Engine.at(160), total: .seconds(150)))
        let atA1 = try Engine.run([Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 40)], on: session)
        #expect(atA1.state.rest == nil)
        #expect(Self.own(atA1.effects) == [.haptic(.setLogged), .cancelRestNotification])
    }
}
