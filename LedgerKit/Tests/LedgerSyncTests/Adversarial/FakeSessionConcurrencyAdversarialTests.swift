import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: `FakeWorkoutSessionClient` called from many tasks at once. Whatever order
/// the calls land in, the updates must be one valid history of the engine (each update is `reduce` of the
/// one before with exactly one of the events, each event once), the same for every subscriber, and every
/// returned state must be the update of its own event. Outcomes that depend on which task won are checked
/// as sets, never as an order.
@Suite("Adversarial F10 S1 · fake session under concurrency", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionConcurrencyAdversarialTests {
    @Test("Sixteen tasks adding and logging sets at once: one engine history, the same for both subscribers")
    func appliesAtOnce_oneHistoryForEverySubscriber() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        #expect(try await Seam.overlapFault(on: fake) == nil)
        #expect(await fake.current()?.doneSets == Seam.overlapTasks * Seam.setsPerTask)
        #expect(await fake.applied.count == 2 * Seam.overlapTasks * Seam.setsPerTask)
    }

    @Test("Streams opened while sets are being added start at some update and then miss none")
    func streamsOpenedDuringApplies_missNoLaterUpdate() async throws {
        let fake = FakeWorkoutSessionClient(live: Seam.session(1))
        #expect(try await Seam.lateJoinFault(on: fake) == nil)
        #expect(await fake.current()?.totalSets == Seam.session(1).totalSets + 400)
    }

    @Test("Streams opened while another task ends the workout start live and then see the end, or start empty")
    func streamsOpenedDuringTheEnd_seeTheEndOrStartEmpty() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let streams = await withTaskGroup(of: AsyncStream<Seam.Update>?.self) { group in
            for number in 0 ..< 60 {
                group.addTask {
                    if number == 30 {
                        _ = await Seam.outcome(of: .discard(Seam.at(77)), on: fake)
                        return nil
                    }
                    return await fake.updates()
                }
            }
            return await group.reduce(into: [AsyncStream<Seam.Update>]()) { $0 += [$1].compactMap(\.self) }
        }
        let discarded = try #require(Seam.engine(live, .discarded(endedAt: Seam.at(77)), in: live.id).0)
        let mark = try await Seam.mark(fake)
        let sawTheEnd = [live, discarded, mark].map { Seam.Update(state: $0) }
        let startedEmpty = [nil, mark].map { Seam.Update(state: $0) }
        #expect(streams.count == 59)
        for stream in streams {
            var reader = SeamReader(stream)
            let heard = await reader.through(mark)
            #expect(heard == sawTheEnd || heard == startedEmpty, "\(heard.map(Seam.brief))")
        }
    }
}
