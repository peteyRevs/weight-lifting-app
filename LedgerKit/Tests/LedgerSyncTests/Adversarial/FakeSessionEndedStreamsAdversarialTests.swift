import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 2 (close-out): streams that end. The fake now forgets a subscriber when a
/// publication finds its stream terminated, and round 1's two tests of its internal count went with the
/// count. What a caller can see is tested here instead: however many streams are dropped or cancelled, with
/// publications between them or none, every stream still read gets every update once, in order.
@Suite("Adversarial F10 S1 · fake session ended streams", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionEndedStreamsAdversarialTests {
    @Test("Five thousand streams dropped while nothing is published disturb no later subscriber or publication")
    func thousandsDroppedWithNoPublication_disturbNoOne() async throws {
        let fake = FakeWorkoutSessionClient()
        for _ in 0 ..< 5000 {
            _ = await fake.updates()
        }
        var kept = await SeamReader(fake)
        let live = Seam.session(1)
        try await fake.start(live)
        let (events, updates) = Seam.edits(50, from: live)
        for event in events {
            try await fake.apply(event)
        }
        var late = await SeamReader(fake)
        let finished = try await fake.finish(endedAt: Seam.at(900))
        let ending = Seam.Update(state: finished, haptics: [.workoutFinished])
        let heard = try await Seam.heard(&kept, on: fake)
        #expect(Seam.difference(
            heard,
            [Seam.Update(state: nil), Seam.Update(state: live)] + updates + [ending],
            "kept"
        ) == nil)
        #expect(await late.next() == Seam.Update(state: updates.last?.state))
        #expect(await late.next() == ending)
    }

    /// Sixty rounds on one workout. In each, streams the seed picks are ended (dropped unread, or read by a
    /// task that is then cancelled), new ones are opened, and one edit is published. A stream still held at
    /// the end must hold its first element and every update since, whatever ended around it.
    @Test(
        "Streams ending among live ones, by a seeded pattern: every stream still read misses and repeats nothing",
        arguments: SeamSeed.all.prefix(40)
    )
    func streamsEndingAmongLiveOnes_disturbNoOne(seed: SeamSeed) async throws {
        var random = SeamRandom(seed: seed.value)
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let (events, updates) = Seam.edits(60, from: live)
        var held: [(joined: Int, stream: AsyncStream<Seam.Update>)] = []
        for (round, event) in events.enumerated() {
            for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
                await held.append((round, fake.updates()))
            }
            for _ in 0 ..< Int.random(in: 0 ... 2, using: &random) where !held.isEmpty {
                let ended = held.remove(at: Int.random(in: 0 ..< held.count, using: &random))
                if Bool.random(using: &random) {
                    let reading = Task { await Seam.buffered(ended.stream).count }
                    #expect(await reading.value == 1 + round - ended.joined)
                }
            }
            try await fake.apply(event)
        }
        #expect(await fake.current() == updates.last?.state)
        for (joined, stream) in held {
            let first = joined == 0 ? live : updates[joined - 1].state
            let expected = [Seam.Update(state: first)] + updates[joined...]
            let difference = await Seam.difference(
                Seam.buffered(stream),
                expected,
                "a stream opened in round \(joined)"
            )
            #expect(difference == nil, "\(seed)")
        }
    }

    @Test("Thirty readers that stop at different points while 300 sets are added: the reader that stays hears all")
    func readersStoppingDuringPublications_disturbNoOne() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let kept = await fake.updates()
        let events = Seam.adds(0 ..< 300)
        let stopped = try await withThrowingTaskGroup(of: [Seam.Update]?.self) { group in
            for reader in 1 ... 30 {
                let stream = await fake.updates()
                group.addTask {
                    var heard: [Seam.Update] = []
                    for await update in stream where heard.count < reader * 5 {
                        heard.append(update)
                        if heard.count == reader * 5 {
                            break
                        }
                    }
                    return heard
                }
            }
            group.addTask {
                for add in events.values {
                    try await fake.apply(add)
                }
                return nil
            }
            return try await group.reduce(into: [[Seam.Update]]()) { $0 += [$1].compactMap(\.self) }
        }
        let history = await Seam.buffered(kept)
        #expect(SeamHistory(history, adds: events).fault == nil && history.count == 301)
        for heard in stopped {
            #expect(heard == Array(history.prefix(heard.count)), "a reader that stopped after \(heard.count)")
        }
        // The readers that stopped are gone; a stream opened now starts where the workout stands.
        var late = await SeamReader(fake)
        #expect(await late.next() == Seam.Update(state: history.last?.state))
    }
}
