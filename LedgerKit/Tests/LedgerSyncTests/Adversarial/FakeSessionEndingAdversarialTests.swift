import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1, criterion 4 at its edges: how a workout ends on `FakeWorkoutSessionClient`
/// by `finish`, by `discard` and by a terminal event through `apply`; and what an end date that is not finite
/// does (the engine ignores it, ADR-004 "Malformed envelopes", so `finish` and `discard` refuse it).
@Suite("Adversarial F10 S1 · fake session ending", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionEndingAdversarialTests {
    /// A way to end a workout, and whether it is the finishing kind.
    struct Ending: Sendable, CustomStringConvertible {
        let description: String
        let finishes: Bool
        let call: @Sendable (Date) -> SeamCall
    }

    static let endings = [
        Ending(description: "finish", finishes: true) { .finish($0) },
        Ending(description: "apply(.finished)", finishes: true) { .apply(.finished(endedAt: $0)) },
        Ending(description: "discard", finishes: false) { .discard($0) },
        Ending(description: "apply(.discarded)", finishes: false) { .apply(.discarded(endedAt: $0)) }
    ]

    /// A workout mid-rest with two sets logged: what an end has to freeze and clear.
    static func midRest(_ fake: FakeWorkoutSessionClient) async throws -> WorkoutState {
        try await fake.start(Seam.session(1))
        try await fake.apply(Seam.logged(0, 0, in: 1, at: 30))
        return try await fake.apply(Seam.logged(0, 1, in: 1, at: 200))
    }

    @Test(
        "Criterion 4: each way of ending returns and publishes the engine's ended state once, then nothing is live",
        arguments: endings
    )
    func ending_publishesTheEndedStateOnce_thenNothingIsLive(_ ending: Ending) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let live = try await Self.midRest(fake)
        #expect(live.rest != nil)
        let before = try await Seam.heard(&reader, on: fake, mark: 1).count
        let marked = try #require(await fake.current())
        let endedAt = Seam.at(1234.5)
        let ended = try #require(Seam.engine(marked, ending.call(endedAt).event, in: marked.id).0)
        #expect(ended.phase == (ending.finishes ? .finished : .discarded))
        #expect(ended.endedAt == endedAt && ended.rest == nil && ended.doneSets == 2)

        let outcome = await Seam.outcome(of: ending.call(endedAt), on: fake)
        let returnsState = ending.description != "discard"
        #expect(outcome == (returnsState ? .state(ended) : .returned))
        #expect(await fake.current() == nil)
        var late = await SeamReader(fake)
        #expect(await late.next() == Seam.Update(state: nil))
        let haptics: [Haptic] = ending.finishes ? [.workoutFinished] : []
        #expect(try await Seam.heard(&reader, on: fake, mark: 2) == [Seam.Update(state: ended, haptics: haptics)])
        #expect(before == 4)
    }

    @Test(
        "Criterion 4: after an end the old subscribers stay subscribed and see the next workout start",
        arguments: endings
    )
    func ending_keepsOldSubscribers_whoSeeTheNextWorkout(_ ending: Ending) async throws {
        let first = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: first)
        var reader = await SeamReader(fake)
        let outcome = await Seam.outcome(of: ending.call(Seam.at(600)), on: fake)
        #expect(outcome != .refused(.noLiveWorkout))
        // The same id again: the fake keeps no history, so the engine's answer (it starts) is the rule.
        var again = first
        again.startedAt = Seam.at(700)
        try await fake.start(again)
        let logged = try await fake.apply(Seam.logged(1, 0, in: 1, at: 760))
        let heard = try await Seam.heard(&reader, on: fake)
        #expect(heard.map(\.state?.phase) == [.live, ending.finishes ? .finished : .discarded, .live, .live])
        #expect(heard.dropFirst(2).map(\.state) == [again, logged])
        #expect(heard.last?.haptics == [.setLogged])
    }

    @Test("No validation window: a finite end date is accepted however far it lies from the start", arguments: endings)
    func ending_anyFiniteDate_isAccepted(_ ending: Ending) async {
        for endedAt in [Date.distantPast, .distantFuture, Seam.at(-1), Date(timeIntervalSinceReferenceDate: 1e300)] {
            let fake = FakeWorkoutSessionClient(live: Seam.session(1))
            #expect(await Seam.outcome(of: ending.call(endedAt), on: fake) != .refused(.noLiveWorkout))
            #expect(await fake.current() == nil, "\(ending) at \(endedAt.timeIntervalSinceReferenceDate)")
        }
    }

    /// F10-S1-1, as ruled after round 1: criterion 4 now says that when the workout is still live after the
    /// call (the engine ignored the end, as it does for a date that is not finite), `finish` and `discard`
    /// throw `invalidEndDate`, end nothing and publish nothing. These two tests documented the old behaviour
    /// (the workout returned still live) and now pin the ruled one.
    @Test(
        "F10-S1-1: finish with a date that is not finite throws invalidEndDate and leaves the workout live",
        arguments: Seam.nonFinite
    )
    func finish_nonFiniteDate_throwsInvalidEndDate_leavingTheWorkoutLive(_ never: Date) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let live = try await Self.midRest(fake)
        #expect(await Seam.outcome(of: .finish(never), on: fake) == .refused(.invalidEndDate))
        #expect(await fake.current() == live)
        let heard = try await Seam.heard(&reader, on: fake)
        #expect(heard.count == 4 && heard.last?.state == live, "the refused finish published something")
        #expect(await Seam.outcome(of: .finish(Seam.at(900)), on: fake) != .refused(.noLiveWorkout))
        #expect(await fake.current() == nil)
    }

    @Test(
        "F10-S1-1: discard with a date that is not finite throws invalidEndDate and discards nothing",
        arguments: Seam.nonFinite
    )
    func discard_nonFiniteDate_throwsInvalidEndDate_leavingTheWorkoutLive(_ never: Date) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let live = try await Self.midRest(fake)
        #expect(await Seam.outcome(of: .discard(never), on: fake) == .refused(.invalidEndDate))
        #expect(await fake.current() == live)
        let heard = try await Seam.heard(&reader, on: fake)
        #expect(heard.count == 4 && heard.last?.state == live, "the refused discard published something")
        // What the caller of "Discard and start new" meets next (brief criterion 2):
        #expect(await Seam.outcome(of: .start(Seam.session(2)), on: fake) == .refused(.workoutInProgress(live.id)))
    }
}
