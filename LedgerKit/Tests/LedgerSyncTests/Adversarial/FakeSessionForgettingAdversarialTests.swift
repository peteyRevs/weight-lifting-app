import Foundation
import LedgerDomain
@testable import LedgerFakes
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: does `FakeWorkoutSessionClient` hold on to streams nobody reads any more?
/// Its documentation says a stream that ended (its consumer's task was cancelled, or the stream was dropped)
/// is forgotten at the next subscription or publication. `subscriberCount` is the fake's own internal count,
/// read through `@testable`.
@Suite("Adversarial F10 S1 · fake session forgets ended streams", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionForgettingAdversarialTests {
    @Test("Thousands of streams opened and dropped while nothing happens are not kept")
    func thousandsOfDroppedStreams_areForgotten() async throws {
        let fake = FakeWorkoutSessionClient()
        for _ in 0 ..< 5000 {
            _ = await fake.updates()
        }
        // Each subscription forgets the streams that ended before it: at most the last is still held.
        #expect(await fake.subscriberCount <= 1)
        var kept = await SeamReader(fake)
        #expect(await fake.subscriberCount == 1)
        try await fake.start(Seam.session(1))
        #expect(await fake.subscriberCount == 1)
        #expect(await kept.next() == Seam.Update(state: nil))
        #expect(await kept.next() == Seam.Update(state: Seam.session(1)))
    }

    @Test("Streams dropped and cancelled during a workout are forgotten at the next publication")
    func streamsEndedMidWorkout_areForgottenAtTheNextPublication() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        var kept = await SeamReader(fake)
        for round in 0 ..< 200 {
            let stream = await fake.updates()
            let reading = Task {
                var count = 0
                for await _ in stream {
                    count += 1
                }
                return count
            }
            reading.cancel()
            _ = await reading.value
            try await fake.apply(.setAdded(exerciseIndex: 0, set: Seam.freshSet(round)))
        }
        // The kept stream, and at most the reader of the last round if its end was noted after the last apply.
        #expect(await fake.subscriberCount <= 2)
        try await fake.apply(.restSkipped)
        #expect(await fake.subscriberCount == 1)
        #expect(try await Seam.heard(&kept, on: fake).count == 202)
    }
}
