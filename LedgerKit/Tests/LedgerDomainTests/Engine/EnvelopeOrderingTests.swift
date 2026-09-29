import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("EventEnvelope · ordering (rule 12)", .tags(.domain))
struct EnvelopeOrderingTests {
    private func envelope(_ seconds: TimeInterval, _ device: DeviceID, _ seq: UInt64) -> EventEnvelope {
        Engine.envelope(.restSkipped, seconds, from: device, seq: seq)
    }

    /// Any 16 bytes (`UUID.random(using:)` needs iOS 26.4).
    private func randomUUID(using rng: inout SeededGenerator) -> UUID {
        let bytes = (0 ..< 16).map { _ in UInt8.random(in: 0 ... 255, using: &rng) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @Test("Wall clock orders first, whatever the device and seq")
    func order_wallClockFirst() {
        #expect(envelope(1, Engine.watch, 9) < envelope(2, Engine.phone, 1))
        #expect(!(envelope(2, Engine.phone, 1) < envelope(1, Engine.watch, 9)))
    }

    @Test("Equal wall clocks order by device ID, as its uuidString sorts")
    func order_tieBreaksOnDevice() {
        #expect(envelope(5, Engine.phone, 9) < envelope(5, Engine.watch, 1))
        #expect(!(envelope(5, Engine.watch, 1) < envelope(5, Engine.phone, 9)))
    }

    @Test("Equal wall clocks and devices order by seq")
    func order_tieBreaksOnSeq() {
        #expect(envelope(5, Engine.watch, 1) < envelope(5, Engine.watch, 2))
        #expect(!(envelope(5, Engine.watch, 2) < envelope(5, Engine.watch, 1)))
        #expect(!(envelope(5, Engine.watch, 2) < envelope(5, Engine.watch, 2)))
    }

    @Test("The key is (device, seq)")
    func key_isDeviceAndSeq() {
        #expect(envelope(5, Engine.watch, 3).key == EnvelopeKey(device: Engine.watch, seq: 3))
        #expect(envelope(5, Engine.watch, 3).key == envelope(9, Engine.watch, 3).key)
        #expect(envelope(5, Engine.watch, 3).key != envelope(5, Engine.phone, 3).key)
    }

    @Test(
        "The order is total on distinct keys and matches the brief's (wallClock, uuidString, seq)",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func order_isTotal_andMatchesUUIDStringOrder(seed: PropertySeed) {
        var rng = seed.generator
        let devices = (0 ..< 3).map { _ in DeviceID(randomUUID(using: &rng)) }
        let envelopes = (1 ... 12).map { seq in
            let device = devices[Int.random(in: 0 ..< 3, using: &rng)]
            return envelope(Double(Int.random(in: 0 ... 3, using: &rng)), device, UInt64(seq))
        }
        #expect(envelopes.sorted() == envelopes.sorted(by: ModelOracle.precedes))
        for lhs in envelopes {
            for rhs in envelopes where lhs.key != rhs.key {
                #expect((lhs < rhs) != (rhs < lhs))
            }
        }
    }
}
