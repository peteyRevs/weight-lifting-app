import Dependencies
import Foundation
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Synchronization
import Testing

/// F17 S7b: the phone's composition builds store → transports → host and connects them. WatchConnectivity is the
/// phone side of a `FakeLiveNetwork` (its link up), mirroring runs over a `FakeHealthStore`'s channel (down), and
/// each test waits on what the network is handed.
@MainActor
@Suite("Live sync wiring", .timeLimit(.minutes(1)))
struct LiveSyncWiringTests {
    /// The hooks the composition hands the health store it makes.
    final class Hooks: Sendable {
        let given = Mutex<HealthHooks?>(nil)

        var hooks: HealthHooks? {
            given.withLock { $0 }
        }
    }

    static let workout = EventBuilders.seedSession()

    /// The keys of the `.envelopes` frame `frame` is, nil for another frame.
    static func keys(_ frame: WireFrame?) -> [EnvelopeKey]? {
        guard case let .envelopes(envelopes) = frame else {
            return nil
        }
        return envelopes.map(\.key)
    }

    @Test("Resuming connects the host: an own envelope reaches the watch, and liveConnection is the transport")
    func resume_connectsTheHost() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let network = FakeLiveNetwork(seed: 17)
        let composition = harness.composition(healthStore: FakeHealthStore(), watchConnectivity: network.phone)
        composition.boot()
        await composition.resume(in: .active)
        var handed = network.phone.handed.makeAsyncIterator()
        let session = try #require(composition.session)
        try await session.start(Self.workout)
        let device = try #require(composition.stores?.deviceID)
        #expect(await Self.keys(handed.next()) == [EnvelopeKey(device: device, seq: 1)])
        let bound = withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.liveConnection) var connection
            return connection
        }
        #expect(bound as? CompositeTransport === composition.transport)
        var states = await bound.states().makeAsyncIterator()
        #expect(await states.next() != nil)
    }

    @Test("watchTookPart is the host's hasWatchParticipant: true once an envelope of the watch's is in the log")
    func watchTookPart_isTheHosts() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let hooks = Hooks()
        let composition = harness.composition(makeHealthStore: { given in
            hooks.given.withLock { $0 = given }
            return FakeHealthStore()
        })
        composition.boot()
        let session = try #require(composition.session)
        let watchTookPart = try #require(hooks.hooks?.watchTookPart)
        try await session.start(Self.workout)
        #expect(await watchTookPart(Self.workout.id) == false)
        let fromWatch = EventBuilders.envelope(
            .restSkipped,
            device: EventBuilders.watch,
            seq: 1,
            at: Harness.now,
            workoutID: Self.workout.id
        )
        try await session.receive([fromWatch])
        #expect(await watchTookPart(Self.workout.id) == true)
        #expect(await session.hasWatchParticipant(Self.workout.id) == true)
    }

    @Test("A mirrored start connects the host when no scene resumed it (a background launch)")
    func mirrorStart_connectsTheHost() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let hooks = Hooks()
        let network = FakeLiveNetwork(seed: 18)
        let composition = harness.composition(
            makeHealthStore: { given in
                hooks.given.withLock { $0 = given }
                return FakeHealthStore()
            },
            watchConnectivity: network.phone
        )
        composition.boot()
        let onMirrorStart = try #require(hooks.hooks?.onMirrorStart)
        await onMirrorStart(nil)
        var handed = network.phone.handed.makeAsyncIterator()
        let session = try #require(composition.session)
        try await session.start(Self.workout)
        #expect(await Self.keys(handed.next())?.map(\.seq) == [1])
    }

    @Test("Without a WatchConnectivity channel nothing is connected and no live connection is bound")
    func noChannel_noLiveSync() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(healthStore: FakeHealthStore())
        composition.boot()
        await composition.resume(in: .active)
        #expect(composition.transport == nil)
        #expect(composition.healthStore is FakeHealthStore)
    }
}
