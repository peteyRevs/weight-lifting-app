import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Synchronization

/// Two hosts, a phone and a watch, over one `FakeLiveNetwork` (F17 S4b): the harness of the live-sync property
/// tests. One task drives it, step by step, and every step ends with both hosts at rest, so a seed decides the
/// whole run:
/// - the network moves only when the test says (`step(by:)`, `settle()`), and what it delivers is handed to one
///   host, which takes all of it, then to the other;
/// - each host takes frames and link changes through a `GatedStream`, so the harness knows when it has dealt
///   with the last one;
/// - each host's sender is drained by a marker: a handshake for a workout nobody has, which the host answers in
///   its turn, after everything it queued before. Its transport swallows the reply instead of sending it.
struct LiveSyncPair {
    /// One device: its host, its stores and its end of the network.
    struct Side {
        let device: DeviceID
        let stores: InMemoryStores
        let host: LocalWorkoutSessionActor
        let transport: HarnessTransport

        /// The stored log of `workout`, in the engine's order.
        func log(of workout: WorkoutID = Sample.session.id) async -> [EventEnvelope] {
            await stores.events.envelopes(for: workout).sorted()
        }

        /// Returns once the host has dealt with every frame and link change handed to it, and its sender has
        /// handed the network everything the host queued.
        func rest() async {
            await transport.links.idle()
            await transport.frames.idle()
            let marker = transport.newMarker()
            try? await host.receive(.handshake(workoutID: marker, contiguousSeq: [:]))
            await transport.sent(marker)
        }
    }

    let network: FakeLiveNetwork
    /// Both hosts' date: one wall clock, so no received stamp is ever beyond the drift bound.
    let clock: SettableClock
    let phone: Side
    let watch: Side

    var sides: [Side] {
        [phone, watch]
    }

    /// Both hosts connected over a network whose chance is `seed`'s, on `link`.
    static func make(seed: UInt64, link: FakeLiveNetwork.Link = .init()) async -> LiveSyncPair {
        let pair = LiveSyncPair(network: FakeLiveNetwork(link: link, seed: seed))
        for side in pair.sides {
            side.transport.links.feed(true)
            await side.host.connect(side.transport, clock: ManualClock())
        }
        return pair
    }

    private init(network: FakeLiveNetwork) {
        self.network = network
        let date = SettableClock()
        clock = date
        func side(_ device: DeviceID, _ transport: FakeLiveWorkoutTransport) -> Side {
            let stores = InMemoryStores()
            let host = LocalWorkoutSessionActor(
                events: stores.events, workouts: stores.workouts, programs: stores.programs,
                device: device, now: { date.now }
            )
            return Side(device: device, stores: stores, host: host, transport: HarnessTransport(transport))
        }
        phone = side(EventBuilders.phone, network.phone)
        watch = side(EventBuilders.watch, network.watch)
    }

    /// The other device's side.
    func peer(of side: Side) -> Side {
        side.device == phone.device ? watch : phone
    }

    /// Moves the network on by `interval` and lets each host deal with what arrived; returns how many frames did.
    @discardableResult
    func step(by interval: Duration) async -> Int {
        network.advance(by: interval)
        return await handOver()
    }

    /// Delivers everything in flight, and what the hosts send back, until nothing is left; returns how many rounds
    /// carried a frame. Stops after `limit` rounds: two hosts that keep answering each other never settle.
    @discardableResult
    func settle(limit: Int = 20) async -> Int {
        var rounds = 0
        while rounds < limit {
            network.flush()
            guard await handOver() > 0 else {
                return rounds
            }
            rounds += 1
        }
        return rounds
    }

    func partition() async {
        network.partition()
        await setLink(false)
    }

    func heal() async {
        network.heal()
        await setLink(true)
    }

    /// Both hosts' workout equal, and equal to the replay of every envelope either device made.
    func converged(on workout: WorkoutID = Sample.session.id) async throws -> Bool {
        let (phoneLog, watchLog) = await (phone.log(of: workout), watch.log(of: workout))
        let made = phoneLog.filter { $0.device == phone.device } + watchLog.filter { $0.device == watch.device }
        let expected = WorkoutEngine.replay(made.sorted())
        let states = try await (phone.host.current(), watch.host.current())
        return phoneLog == watchLog && states.0 == expected && states.1 == expected
    }

    /// Ends the hosts' streams, so no listener is left waiting.
    func close() {
        for side in sides {
            side.transport.frames.finish()
            side.transport.links.finish()
        }
    }

    private func setLink(_ isUp: Bool) async {
        for side in sides {
            side.transport.links.feed(isUp)
            await side.rest()
        }
    }

    /// The frames the network delivered since the last hand-over, to one host and then the other.
    private func handOver() async -> Int {
        var count = 0
        for side in sides {
            count += side.transport.feedDelivered()
            await side.rest()
        }
        return count
    }
}

/// A host's end of the network in the harness: sends through a `FakeLiveWorkoutTransport`, and takes frames and
/// link changes from `GatedStream`s the harness feeds, so the harness can wait for the host to deal with them.
final class HarnessTransport: LiveWorkoutTransport {
    private struct State {
        var fed = 0
        var markers: Set<WorkoutID> = []
        var sentMarkers: Set<WorkoutID> = []
        var waiters: [WorkoutID: CheckedContinuation<Void, Never>] = [:]
        var nextMarker = 0
    }

    let base: FakeLiveWorkoutTransport
    let frames = GatedStream<WireFrame>()
    let links = GatedStream<Bool>()
    let incoming: AsyncStream<WireFrame>
    let link: AsyncStream<Bool>
    private let state = Mutex(State())

    init(_ base: FakeLiveWorkoutTransport) {
        self.base = base
        incoming = frames.makeStream()
        link = links.makeStream()
    }

    func send(_ frame: WireFrame) async throws {
        if case let .handshake(workout, _) = frame, isMarker(workout) {
            let waiter = state.withLock { state in
                guard let waiter = state.waiters.removeValue(forKey: workout) else {
                    state.sentMarkers.insert(workout)
                    return CheckedContinuation<Void, Never>?.none
                }
                return waiter
            }
            waiter?.resume()
            return
        }
        try await base.send(frame)
    }

    /// Feeds the host every frame the network delivered here since the last call; returns how many.
    func feedDelivered() -> Int {
        let fresh = state.withLock { state in
            let received = base.received
            defer { state.fed = received.count }
            return Array(received.dropFirst(state.fed))
        }
        fresh.forEach(frames.feed)
        return fresh.count
    }

    /// A workout nobody has: the host's handshake for it is swallowed here (`sent(_:)`).
    func newMarker() -> WorkoutID {
        state.withLock { state in
            state.nextMarker += 1
            let marker = WorkoutID(EventBuilders.uuid(0x0E00_0000 + state.nextMarker))
            state.markers.insert(marker)
            return marker
        }
    }

    /// Returns once the host's sender has reached `marker`'s handshake.
    func sent(_ marker: WorkoutID) async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let reached = state.withLock { state in
                guard state.sentMarkers.remove(marker) == nil else {
                    return true
                }
                state.waiters[marker] = waiter
                return false
            }
            if reached {
                waiter.resume()
            }
        }
    }

    private func isMarker(_ workout: WorkoutID) -> Bool {
        state.withLock { $0.markers.contains(workout) }
    }
}
