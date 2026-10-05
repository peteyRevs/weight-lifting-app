import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1, criterion 1 at its edges: `FakeWorkoutSessionClient.updates()` for a
/// subscriber that arrives before a workout, during one and after it; many subscribers; one that reads
/// nothing until the end; one cancelled mid-workout; and one that calls back from inside its loop. Nothing
/// waits on a clock: readers stop at a mark or at an acknowledgement.
@Suite("Adversarial F10 S1 · fake session streams", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionStreamsAdversarialTests {
    @Test("Criterion 1: a stream's first element is the workout as it stands, never with effects, wherever it joins")
    func firstElement_isTheWorkoutAsItStands_withoutEffects() async throws {
        let fake = FakeWorkoutSessionClient()
        var before = await SeamReader(fake)
        #expect(await before.next() == Seam.Update(state: nil))
        try await fake.start(Seam.session(1))
        var atStart = await SeamReader(fake)
        #expect(await atStart.next() == Seam.Update(state: Seam.session(1)))
        // Straight after a buzz: the haptic belongs to the update, not to the next stream's first element.
        let logged = try await fake.apply(Seam.logged(0, 0, in: 1))
        var afterLog = await SeamReader(fake)
        #expect(await afterLog.next() == Seam.Update(state: logged))
        let finished = try await fake.finish(endedAt: Seam.at(900))
        var afterEnd = await SeamReader(fake)
        #expect(await afterEnd.next() == Seam.Update(state: nil))
        #expect(await before.next() == Seam.Update(state: Seam.session(1)))
        #expect(await before.next() == Seam.Update(state: logged, effects: [.haptic(.setLogged)]))
        #expect(await before.next() == Seam.Update(state: finished, effects: [.haptic(.workoutFinished)]))
        #expect(await atStart.next() == Seam.Update(state: logged, effects: [.haptic(.setLogged)]))
        #expect(await afterLog.next() == Seam.Update(state: finished, effects: [.haptic(.workoutFinished)]))
    }

    @Test("Criterion 1: fifty subscribers, joining one per change, each get every later update in order")
    func fiftySubscribers_eachGetEveryLaterUpdate() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let (events, updates) = Seam.edits(50, from: live)
        var streams: [AsyncStream<Seam.Update>] = []
        for event in events {
            await streams.append(fake.updates())
            try await fake.apply(event)
        }
        let mark = try await Seam.mark(fake)
        for (joined, stream) in streams.enumerated() {
            var reader = SeamReader(stream)
            let first = joined == 0 ? live : updates[joined - 1].state
            let expected = [Seam.Update(state: first)] + updates[joined...] + [Seam.Update(state: mark)]
            let difference = await Seam.difference(reader.through(mark), expected, "subscriber \(joined)")
            #expect(difference == nil)
        }
    }

    @Test("A subscriber that reads nothing until the end loses nothing: 5,000 updates, in order")
    func slowSubscriber_readsNothingUntilTheEnd_losesNothing() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        var slow = await SeamReader(fake)
        let (events, updates) = Seam.edits(5000, from: live)
        for event in events {
            try await fake.apply(event)
        }
        let finished = try await fake.finish(endedAt: Seam.at(9000))
        let expected = [Seam.Update(state: live)] + updates
            + [Seam.Update(state: finished, effects: [.haptic(.workoutFinished)])]
        let heard = try await Seam.heard(&slow, on: fake)
        #expect(Seam.difference(heard, expected, "the slow subscriber") == nil)
    }

    @Test("A subscriber cancelled mid-workout ends there; the others miss nothing afterwards")
    func cancelledSubscriber_endsThere_othersMissNothing() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        var kept = await SeamReader(fake)
        let doomed = await fake.updates()
        let (acknowledged, acknowledge) = AsyncStream.makeStream(of: Int.self)
        let listening = Task {
            var heard: [Seam.Update] = []
            for await update in doomed {
                heard.append(update)
                acknowledge.yield(heard.count)
            }
            return heard
        }
        let (events, updates) = Seam.edits(6, from: live)
        var acknowledgements = acknowledged.makeAsyncIterator()
        for event in events.prefix(3) {
            try await fake.apply(event)
        }
        // The doomed reader has read all four (the first element and three edits) before it is cancelled.
        while let count = await acknowledgements.next(), count < 4 {}
        listening.cancel()
        #expect(await listening.value == [Seam.Update(state: live)] + updates.prefix(3))
        for event in events.dropFirst(3) {
            try await fake.apply(event)
        }
        #expect(try await Seam.heard(&kept, on: fake) == [Seam.Update(state: live)] + updates)
        var late = await SeamReader(fake)
        #expect(await late.next()?.state == fake.current())
    }

    @Test("A subscriber that applies an event from inside its loop does not deadlock, and sees its own update")
    func subscriberThatCallsBack_seesItsOwnUpdates() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        let stream = await fake.updates()
        let sets = live.totalSets
        let chain = Task {
            var heard = 0
            for await update in stream {
                heard += 1
                guard let state = update.live, state.totalSets < sets + 200 else {
                    break
                }
                try await fake.apply(.setAdded(exerciseIndex: 0, set: Seam.freshSet(state.totalSets)))
            }
            return heard
        }
        #expect(try await chain.value == 201)
        #expect(await fake.current()?.totalSets == sets + 200)
    }
}
