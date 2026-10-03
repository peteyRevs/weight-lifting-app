import LedgerTestSupport
import Testing

/// `FakeLinkBus`, the in-memory network sync tests run on (F07 criterion 5): loss, duplication, delay and
/// partitions, all from a seeded generator and the bus's own time, so every run is the same.
@Suite("FakeLinkBus")
struct FakeTransportTests {
    typealias Bus = FakeLinkBus<Int>

    /// Sends 0 ..< count from endpoint 0 to endpoint 1, then delivers everything.
    static func sendAll(_ count: Int, over bus: Bus) -> [Int] {
        let (phone, watch) = (bus.endpoints[0], bus.endpoints[1])
        for number in 0 ..< count {
            bus.send(number, from: phone, to: watch)
        }
        bus.flush()
        return bus.received(by: watch).map(\.payload)
    }

    @Test("Criterion 5: two endpoints, loss 0.3, 100 envelopes: at least 70 arrive, and none twice")
    func test_lossy_deliversAtLeast70_neverADuplicate() {
        let bus = Bus(endpoints: 2, link: .init(loss: 0.3), seed: 2026)
        let received = Self.sendAll(100, over: bus)
        #expect(received.count >= 70)
        #expect(Set(received).count == received.count)
        #expect(received == received.sorted())
    }

    @Test("Loss 0.3 loses about 30 % over many seeds, and no seed ever duplicates")
    func lossyLink_losesAboutItsRate_overSeeds() {
        var total = 0
        for seed in 0 ..< UInt64(200) {
            let received = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(loss: 0.3), seed: seed))
            #expect(Set(received).count == received.count, "seed \(seed)")
            total += received.count
        }
        #expect((13700 ... 14300).contains(total)) // 200 × 70 ± about 4.6 standard deviations
    }

    @Test("The same seed and calls deliver the same messages; another seed loses others")
    func sameSeed_sameDeliveries() {
        let first = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(loss: 0.5), seed: 7))
        let again = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(loss: 0.5), seed: 7))
        let other = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(loss: 0.5), seed: 8))
        #expect(first == again)
        #expect(first != other)
    }

    @Test("Duplicates arrive only when configured")
    func duplicates_onlyWhenConfigured() {
        let none = Self.sendAll(100, over: Bus(endpoints: 2, seed: 1))
        let doubled = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(duplication: 1), seed: 1))
        let some = Self.sendAll(100, over: Bus(endpoints: 2, link: .init(duplication: 0.2), seed: 1))
        #expect(none == Array(0 ..< 100))
        #expect(doubled == (0 ..< 100).flatMap { [$0, $0] })
        #expect(some.count > 100 && Set(some) == Set(0 ..< 100))
    }

    @Test("A delayed message arrives once the bus's time reaches it, in arrival order")
    func delay_deliversWhenDue_inArrivalOrder() {
        let bus = Bus(endpoints: 2, link: .init(delay: .milliseconds(10) ... .milliseconds(500)), seed: 3)
        let (phone, watch) = (bus.endpoints[0], bus.endpoints[1])
        for number in 0 ..< 50 {
            bus.send(number, from: phone, to: watch)
        }
        bus.advance(by: .milliseconds(5))
        #expect(bus.received(by: watch).isEmpty && bus.inFlightCount == 50)
        bus.advance(by: .milliseconds(250))
        let early = bus.received(by: watch)
        #expect(!early.isEmpty && early.count < 50)
        #expect(early.allSatisfy { $0.arrival <= .milliseconds(255) && $0.from == phone })
        bus.flush()
        let all = bus.received(by: watch)
        #expect(Set(all.map(\.payload)) == Set(0 ..< 50) && bus.inFlightCount == 0)
        #expect(all.map(\.arrival) == all.map(\.arrival).sorted())
        #expect(all.map(\.payload) != Array(0 ..< 50)) // the delays reorder them
    }

    @Test("A partition loses what is sent across it and what was on its way; healing restores the link")
    func partition_losesTraffic_untilHealed() {
        let bus = Bus(endpoints: 3, link: .init(delay: .seconds(1) ... .seconds(1)), seed: 4)
        let (phone, watch, ipad) = (bus.endpoints[0], bus.endpoints[1], bus.endpoints[2])
        bus.send(1, from: phone, to: watch)
        bus.partition(phone, watch)
        bus.send(2, from: watch, to: phone)
        bus.broadcast(3, from: phone)
        bus.flush()
        #expect(bus.received(by: watch).isEmpty && bus.received(by: phone).isEmpty)
        #expect(bus.received(by: ipad).map(\.payload) == [3])
        bus.heal(watch, phone)
        bus.send(4, from: phone, to: watch)
        bus.flush()
        #expect(bus.received(by: watch).map(\.payload) == [4])
    }

    @Test("setLink changes how later messages travel")
    func setLink_appliesToLaterMessages() {
        let bus = Bus(endpoints: 2, seed: 5)
        bus.setLink(.init(loss: 1))
        #expect(Self.sendAll(10, over: bus).isEmpty)
        bus.setLink(.init())
        #expect(Self.sendAll(10, over: bus) == Array(0 ..< 10))
    }
}
