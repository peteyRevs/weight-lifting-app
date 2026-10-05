import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: calls that race for the same workout on `FakeWorkoutSessionClient`: many
/// starts at once, a finish against a stream of applies, and many ends at once. Exactly one call may win
/// each race; the others must be refused as if they had come after it, and the stream must tell one story.
/// Which task wins is the scheduler's choice, so the outcomes are checked as sets, never as an order.
@Suite("Adversarial F10 S1 · fake session races", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionRacesAdversarialTests {
    @Test("Fifty starts at once: one wins, the rest are refused naming the winner, one update is published")
    func startsAtOnce_oneWins_theRestAreRefused() async throws {
        let fake = FakeWorkoutSessionClient()
        #expect(try await Seam.startRaceFault(on: fake) == nil)
        #expect(await fake.applied.count == 50)
    }

    @Test("Finish racing eight tasks of applies: every apply lands before the end or is refused after it")
    func finishRacingApplies_appliesLandBeforeTheEndOrAreRefused() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        #expect(try await Seam.applyVersusEndFault(on: fake) == nil)
        #expect(await fake.current() == nil)
    }

    @Test("Twenty finishes and twenty discards at once: exactly one ends the workout, in one update")
    func endsAtOnce_exactlyOneEndsTheWorkout() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        #expect(try await Seam.endRaceFault(on: fake) == nil)
        #expect(await fake.applied.count == 40)
    }
}
