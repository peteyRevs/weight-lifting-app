import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 2 (close-out), criterion 4 as revised: when the workout is still live after
/// the call because the engine ignored the end, `finish` and `discard` throw `invalidEndDate`, end nothing
/// and publish nothing. Through `apply` such an end is an ignored event like any other, and with nothing
/// live it is `noLiveWorkout`. Also the two races the fix round's rules name and round 1 did not run.
@Suite("Adversarial F10 S1 · fake session invalid end", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionInvalidEndAdversarialTests {
    /// An end at a date the engine ignores, by one of the two methods.
    struct InvalidEnd: Sendable, CustomStringConvertible {
        let description: String
        let call: SeamCall
    }

    static let invalidEnds: [InvalidEnd] = Seam.nonFinite.flatMap { never in
        let date = "\(never.timeIntervalSinceReferenceDate)"
        return [
            InvalidEnd(description: "finish at \(date)", call: .finish(never)),
            InvalidEnd(description: "discard at \(date)", call: .discard(never))
        ]
    }

    @Test(
        "Criterion 4: an end the engine ignores is refused fifty times over, and a valid end still works",
        arguments: invalidEnds
    )
    func invalidEnd_isRefusedEveryTime_thenAValidEndWorks(_ invalid: InvalidEnd) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let live = try await FakeSessionEndingAdversarialTests.midRest(fake)
        for _ in 0 ..< 50 {
            #expect(await Seam.outcome(of: invalid.call, on: fake) == .refused(.invalidEndDate))
        }
        #expect(await fake.current() == live && live.rest != nil)
        var late = await SeamReader(fake)
        #expect(await late.next() == Seam.Update(state: live))
        let applied = await fake.applied
        let asked = Array(repeating: invalid.call.event, count: 50)
        #expect(applied.count == 53 && Seam.sameEvents(Array(applied.suffix(50)), asked))
        // The other kind of end, at a date the engine takes: the engine's ended state, once.
        let valid: SeamCall = invalid.description.hasPrefix("finish") ? .discard(Seam.at(900)) : .finish(Seam.at(900))
        let ended = try #require(Seam.update(after: valid.event, on: live))
        let returned: SeamOutcome = ended.state.flatMap { $0.phase == .finished ? .state($0) : nil } ?? .returned
        #expect(await Seam.outcome(of: valid, on: fake) == returned)
        #expect(await fake.current() == nil)
        // The fifty refusals published nothing: the two logs are followed at once by the end.
        let heard = try await Seam.heard(&reader, on: fake)
        #expect(heard.count == 5 && heard.suffix(2).map(\.state) == [live, ended.state] && heard.last == ended)
        #expect(await late.next() == ended)
    }

    @Test(
        "Criterion 3: the same end through apply is an ignored event: the workout comes back, nothing throws",
        arguments: invalidEnds
    )
    func invalidEnd_throughApply_returnsTheWorkoutUnchanged(_ invalid: InvalidEnd) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let live = try await FakeSessionEndingAdversarialTests.midRest(fake)
        #expect(await Seam.outcome(of: .apply(invalid.call.event), on: fake) == .state(live))
        #expect(await fake.current() == live)
        #expect(try await Seam.heard(&reader, on: fake).count == 4)
    }

    @Test(
        "Criterion 2: with nothing live the same end is noLiveWorkout, before a workout and after one",
        arguments: invalidEnds
    )
    func invalidEnd_withNothingLive_isNoLiveWorkout(_ invalid: InvalidEnd) async throws {
        let fake = FakeWorkoutSessionClient()
        #expect(await Seam.outcome(of: invalid.call, on: fake) == .refused(.noLiveWorkout))
        try await fake.start(Seam.session(1))
        try await fake.discard(endedAt: Seam.at(60))
        #expect(await Seam.outcome(of: invalid.call, on: fake) == .refused(.noLiveWorkout))
        #expect(await fake.current() == nil)
    }

    @Test("Ends the engine ignores racing one that succeeds: only that one returns, and it is the stream's last word")
    func invalidEnds_racingAValidFinish_neverReturn() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        #expect(try await Seam.invalidEndRaceFault(on: fake) == nil)
        #expect(await fake.current() == nil)
    }

    @Test("Ends the engine ignores racing sixty adds end nothing: every one is refused, and the history is whole")
    func invalidEnds_racingApplies_endNothing() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let stream = await fake.updates()
        let events = Seam.adds(0 ..< 60)
        let refused = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                for add in events.values {
                    try await fake.apply(add)
                }
                return 0
            }
            for number in 0 ..< 12 {
                group.addTask {
                    let never = Seam.nonFinite[number % 3]
                    let outcome = await Seam.outcome(of: number < 6 ? .finish(never) : .discard(never), on: fake)
                    return outcome == .refused(.invalidEndDate) ? 1 : 0
                }
            }
            return try await group.reduce(0, +)
        }
        let heard = await Seam.buffered(stream)
        #expect(refused == 12)
        #expect(SeamHistory(heard, adds: events).fault == nil && heard.count == 61)
        #expect(await fake.current()?.totalSets == live.totalSets + 60)
    }

    @Test("A start racing applies: the stream reads no workout, the start, then one history of what landed")
    func startRacingApplies_isPublishedBeforeAnyOfThem() async throws {
        #expect(try await Seam.startVersusApplyFault(on: FakeWorkoutSessionClient()) == nil)
    }

    @Test("A subscriber that acts on the update that started the workout finds it current")
    func subscriberActingOnTheStart_findsTheWorkoutCurrent() async throws {
        #expect(try await Seam.reactionFault(on: FakeWorkoutSessionClient()) == nil)
    }
}
