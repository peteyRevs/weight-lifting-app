import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport

/// The runs `LiveSyncPropertyTests` checks, and what it reads from the frames.
extension LiveSyncPropertyTests {
    /// What a criterion 4 run reached.
    struct Reach {
        var lost = false
        var duplicated = false
        var reordered = false
        var partitioned = false
        var apartBeforeReconnect = false

        mutating func add(_ other: Reach) {
            lost = lost || other.lost
            duplicated = duplicated || other.duplicated
            reordered = reordered || other.reordered
            partitioned = partitioned || other.partitioned
            apartBeforeReconnect = apartBeforeReconnect || other.apartBeforeReconnect
        }
    }

    /// Criterion 4's run of `seed`: the phone starts the workout, then 200 edits drawn from both sides with the
    /// network moving between them on `faulty`, cut by partitions. Then the link is made clean and goes down and
    /// up once: the handshake of a link-up is how a lost frame comes back (S4a), so "flushed" is one reconnect.
    static func faultyRun(seed: UInt64) async throws -> (converged: Bool, reach: Reach) {
        let pair = try await started(seed: seed)
        defer { pair.close() }
        pair.network.setLink(faulty)
        var writer = EditWriter(seed: seed)
        var reach = Reach()
        for _ in 0 ..< 200 {
            try await writer.randomEdit(on: writer.coin() ? pair.phone : pair.watch, pair)
            if writer.chance(0.4) {
                await pair.step(by: .milliseconds(writer.int(in: 0 ... 2500)))
            }
            if writer.chance(0.03) {
                reach.partitioned = true
                if pair.network.isPartitioned {
                    await pair.heal()
                } else {
                    await pair.partition()
                }
            }
        }
        await pair.step(by: .seconds(3)) // past the longest delay: nothing is left in flight
        for side in pair.sides {
            reach.add(faults(seenBy: side, from: pair.peer(of: side)))
        }
        pair.network.setLink(.init())
        reach.apartBeforeReconnect = try await !(pair.converged())
        await pair.partition()
        await pair.heal()
        await pair.settle()
        return try await (pair.converged(), reach)
    }

    /// The faults the frames `side` received show, against the single-envelope frames `peer` sent as it logged:
    /// one that never arrived, one that arrived twice, and two that arrived in the other order.
    static func faults(seenBy side: Side, from peer: Side) -> Reach {
        let sent = peer.transport.base.sent.filter { single($0) != nil }
        let received = side.transport.base.received.filter { single($0) != nil }
        let arrivals = Dictionary(received.map { ($0, 1) }, uniquingKeysWith: +)
        let sends = Dictionary(sent.map { ($0, 1) }, uniquingKeysWith: +)
        let seqs = received.compactMap { single($0)?.seq }
        var reach = Reach()
        reach.lost = sends.keys.contains { arrivals[$0] == nil }
        reach.duplicated = arrivals.contains { $0.value > sends[$0.key, default: 0] }
        reach.reordered = zip(seqs, seqs.dropFirst()).contains { $0 > $1 }
        return reach
    }

    /// The envelope of a frame that carries one, as a host sends each it logs.
    static func single(_ frame: WireFrame) -> EventEnvelope? {
        guard case let .envelopes(envelopes) = frame, envelopes.count == 1 else {
            return nil
        }
        return envelopes[0]
    }

    /// The phone starts the workout on a clean link and the watch takes it up.
    static func started(seed: UInt64) async throws -> LiveSyncPair {
        let pair = await LiveSyncPair.make(seed: seed)
        try await pair.phone.host.start(Sample.session)
        await pair.phone.rest()
        await pair.settle()
        guard try await pair.watch.host.current()?.id == workout else {
            throw LiveSyncError.watchDidNotJoin
        }
        return pair
    }

    enum LiveSyncError: Error {
        case watchDidNotJoin
    }

    /// The keys `side` holds that its peer does not.
    static func lacking(_ side: Side, _ pair: LiveSyncPair) async -> Set<EnvelopeKey> {
        let peer = await Set(pair.peer(of: side).log().map(\.key))
        return await Set(side.log().map(\.key)).subtracting(peer)
    }

    /// Handshakes for the workout, `.envelopes` frames, and the keys they carried (none twice, or the set shrinks).
    static func summary(_ frames: some Collection<WireFrame>) -> Summary {
        var result = Summary()
        var count = 0
        for frame in frames {
            switch frame {
            case let .handshake(id, _) where id == workout:
                result.handshakes += 1
            case let .envelopes(envelopes):
                result.envelopeFrames += 1
                count += envelopes.count
                result.keys.formUnion(envelopes.map(\.key))
            default:
                break
            }
        }
        if count != result.keys.count {
            result.keys = []
        }
        return result
    }

    /// What `summary(_:)` counts.
    struct Summary {
        var handshakes = 0
        var envelopeFrames = 0
        var keys: Set<EnvelopeKey> = []
    }
}
