import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
@testable import LedgerWatchAppKit
import Testing

/// F17 S7b: the watch's composition builds store → transports → host, binds the host, and runs the health events'
/// broadcast and the phone-start rule. WatchConnectivity is the watch side of a `FakeLiveNetwork`; mirroring runs over
/// a `FakeHealthStore`'s channel.
@MainActor
@Suite("Live sync wiring", .timeLimit(.minutes(1)))
struct LiveSyncWiringTests {
    /// A clock whose waits end at once, so the phone-start rule's 5 s pass with no time gone by. It never sleeps.
    struct InstantClock: Clock {
        var now: ContinuousClock.Instant {
            .now
        }

        var minimumResolution: Duration {
            .zero
        }

        func sleep(until _: ContinuousClock.Instant, tolerance _: Duration?) async throws {
            try Task.checkCancellation()
        }
    }

    @Test("Resuming builds and binds the host and connects it: an own envelope reaches the phone")
    func resume_connectsTheHost() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let network = FakeLiveNetwork(seed: 19)
        let composition = harness.composition(healthStore: FakeHealthStore(), watchConnectivity: network.watch)
        composition.boot()
        await composition.resume(in: .active)
        let session = try #require(composition.session)
        let bound = withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.workoutSession) var workoutSession
            @Dependency(\.liveConnection) var liveConnection
            return (workoutSession, liveConnection)
        }
        #expect(bound.0 as? LocalWorkoutSessionActor === session)
        #expect(bound.1 as? CompositeTransport === composition.transport)
        var handed = network.watch.handed.makeAsyncIterator()
        try await session.start(EventBuilders.seedSession())
        guard case let .envelopes(envelopes)? = await handed.next() else {
            Issue.record("the watch's started was not sent")
            return
        }
        #expect(envelopes.map(\.seq) == [1])
    }

    @Test("Criterion 8's wiring: the phone asks, its workout does not come within 5 s, the watch starts its own")
    func phoneStartRequest_withNoPhoneWorkout_startsOwn() async {
        let harness = Harness()
        defer { harness.remove() }
        let (started, startedSink) = AsyncStream<Void>.makeStream()
        let health = FakeHealthStore()
        let composition = harness.composition(
            healthStore: health,
            watchConnectivity: FakeLiveWorkoutTransport(),
            syncClock: InstantClock(),
            startOwnWorkout: { startedSink.yield() }
        )
        composition.boot()
        await composition.resume(in: .active)
        health.noteStartRequestedByPhone() // as WatchAppDelegate.handle(_:) reports it
        var starts = started.makeAsyncIterator()
        #expect(await starts.next() != nil)
    }

    @Test("Without a WatchConnectivity channel the host is still built and bound, and nothing is connected")
    func noChannel_hostOnly() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(healthStore: FakeHealthStore())
        composition.boot()
        await composition.resume(in: .active)
        #expect(composition.session != nil)
        #expect(composition.transport == nil)
    }
}
