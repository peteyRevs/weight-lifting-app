import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S5b, criterion 8's second half (Pete 2026-11-25, option C): of two workouts started on the two devices within
/// 60 s, the earlier `started` goes on live on both; the loser is saved to history on both when it holds set data,
/// and dropped on both when it holds nothing of the lifter's. The two-host tests run on `LiveSyncPair`.
@Suite("LocalWorkoutSessionActor · a double start", .tags(.sync), .timeLimit(.minutes(1)))
struct HostDoubleStartTests {
    typealias Side = LiveSyncPair.Side

    /// The watch's own workout: the superset day, from the watch, started `seconds` after the fixture start.
    static func watchSession(at seconds: Double) -> WorkoutState {
        EventBuilders.session(
            EventBuilders.supersetExercises, id: Sample.other.id, device: EventBuilders.watch,
            startedAt: Sample.at(seconds)
        )
    }

    /// Row (`exerciseIndex`, `setIndex`) of `state` logged now.
    static func logged(_ state: WorkoutState, _ exerciseIndex: Int, _ setIndex: Int, at date: Date) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex, setID: state.exercises[exerciseIndex].sets[setIndex].id,
            weight: .pounds(100), reps: Reps(clamping: 5), doneAt: date
        )
    }

    /// `side`'s saved copy of `workout`, as (phase, rows done), or nil when its history has none.
    static func saved(_ workout: WorkoutID, on side: Side) async throws -> (WorkoutPhase, Int)? {
        try await side.stores.workouts.workout(id: workout).map { state in
            (state.phase, state.exercises.flatMap(\.sets).filter(\.isDone).count)
        }
    }

    enum Loser: String, CaseIterable, CustomStringConvertible {
        case phone, watch

        var description: String {
            rawValue
        }
    }

    @Test(
        "Criterion 8: the earlier start wins on both; a loser with sets is saved on both, an empty one dropped",
        arguments: Loser.allCases,
        [true, false]
    )
    func doubleStart_earlierWins(loser: Loser, withSets: Bool) async throws {
        let pair = await LiveSyncPair.make(seed: 85)
        defer { pair.close() }
        await pair.partition()
        let (phoneSession, watchSession) = (Sample.session, Self.watchSession(at: loser == .watch ? 20 : 0))
        let order = loser == .phone ? [(pair.watch, watchSession), (pair.phone, phoneSession)]
            : [(pair.phone, phoneSession), (pair.watch, watchSession)]
        for (index, (side, session)) in order.enumerated() {
            pair.clock.set(Sample.at(Double(index * 20)))
            try await side.host.start(session)
        }
        let (losing, winning) = loser == .phone ? (pair.phone, pair.watch) : (pair.watch, pair.phone)
        let (lost, won) = loser == .phone ? (phoneSession, watchSession) : (watchSession, phoneSession)
        pair.clock.set(Sample.at(30))
        try await winning.host.apply(Self.logged(won, 0, 0, at: pair.clock.now))
        if withSets {
            try await losing.host.apply(Self.logged(lost, 0, 0, at: pair.clock.now))
            try await losing.host.apply(Self.logged(lost, 1, 0, at: pair.clock.now))
        }
        for side in pair.sides {
            await side.rest()
        }
        await pair.heal()
        await pair.settle()
        #expect(try await pair.converged(on: won.id))
        #expect(try await losing.host.current()?.id == won.id)
        for side in pair.sides {
            #expect(await side.log(of: lost.id).isEmpty, "\(side.device): no log of the loser is left")
            let copy = try await Self.saved(lost.id, on: side)
            #expect(copy?.0 == (withSets ? .finished : nil) && copy?.1 == (withSets ? 2 : nil))
            #expect(try await Self.saved(won.id, on: side) == nil)
        }
    }

    @Test("Starts more than 60 s apart are no double start: each device keeps both, and its own live")
    func startsApart_keepBoth() async throws {
        let pair = await LiveSyncPair.make(seed: 86)
        defer { pair.close() }
        await pair.partition()
        try await pair.phone.host.start(Sample.session)
        pair.clock.set(Sample.at(61))
        try await pair.watch.host.start(Self.watchSession(at: 61))
        await pair.watch.rest()
        await pair.heal()
        await pair.settle()
        #expect(try await pair.phone.host.current()?.id == Sample.session.id)
        #expect(try await pair.watch.host.current()?.id == Sample.other.id)
        for workout in [Sample.session.id, Sample.other.id] {
            let (onPhone, onWatch) = await (pair.phone.log(of: workout), pair.watch.log(of: workout))
            #expect(!onPhone.isEmpty && onPhone == onWatch)
        }
    }

    @Test("A launch that finds an unresolved double start settles it: the winner resumes, the own loser is saved")
    func recovery_resolvesADoubleStart() async throws {
        let subject = Subject()
        subject.clock.set(Sample.at(20))
        try await subject.host.start(Sample.session)
        _ = try await subject.host.apply(Sample.logged(0, 0, at: 21))
        let peer = Self.watchSession(at: 0)
        _ = try await subject.stores.events.append([Peer.envelope(.started(peer), seq: 1, at: 0, of: peer.id)])
        let next = subject.relaunched()
        #expect(try await next.host.resumeFromStore()?.id == peer.id)
        let copy = try await subject.stores.workouts.workout(id: Sample.session.id)
        #expect(copy?.phase == .finished && Peer.isDone(copy, 0, 0))
        #expect(await subject.log(of: Sample.session.id).isEmpty)
    }

    @Test("A saved loser's log coming back from the peer is dropped, never saved over the whole one")
    func savedLoser_returningLog_isNotSavedAgain() async throws {
        let subject = Subject()
        subject.clock.set(Sample.at(20))
        try await subject.host.start(Sample.session)
        _ = try await subject.host.apply(Sample.logged(0, 0, at: 21))
        _ = try await subject.host.apply(Sample.logged(0, 1, at: 22))
        let own = await subject.log(of: Sample.session.id)
        let peer = Self.watchSession(at: 0)
        try await subject.host.receive([Peer.envelope(.started(peer), seq: 1, at: 0, of: peer.id)])
        #expect(try await subject.host.current()?.id == peer.id)
        try await subject.host.receive(Array(own.prefix(2))) // the started and one set, relayed back
        let copy = try await subject.stores.workouts.workout(id: Sample.session.id)
        #expect(Peer.isDone(copy, 0, 0) && Peer.isDone(copy, 0, 1))
        #expect(await subject.log(of: Sample.session.id).isEmpty)
        #expect(try await subject.host.current()?.id == peer.id)
    }
}
