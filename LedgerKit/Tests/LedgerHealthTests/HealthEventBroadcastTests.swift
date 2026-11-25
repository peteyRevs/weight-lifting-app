import LedgerDomain
import LedgerHealth
import Testing

/// F17 S5a: `HealthEventBroadcast`, the store's one-consumer `events` for every reader on the watch.
@Suite("Health event broadcast", .timeLimit(.minutes(1)))
struct HealthEventBroadcastTests {
    typealias Event = HealthSessionEvent

    static func all(_ stream: AsyncStream<Event>) async -> [Event] {
        var events: [Event] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("Every subscriber gets every event in order, held from before the broadcast ran")
    func everySubscriber_getsEveryEvent() async {
        let (source, sink) = AsyncStream<Event>.makeStream()
        let broadcast = HealthEventBroadcast(source)
        let (first, second) = await (broadcast.subscribe(), broadcast.subscribe())
        sink.yield(.prepared)
        sink.yield(.startRequestedByPhone)
        sink.finish()
        await broadcast.run()
        let expected: [Event] = [.prepared, .startRequestedByPhone]
        #expect(await Self.all(first) == expected)
        #expect(await Self.all(second) == expected)
    }

    @Test("A later subscriber gets what comes after it subscribed; a dropped one costs the others nothing")
    func laterSubscriber_getsWhatFollows() async {
        let (source, sink) = AsyncStream<Event>.makeStream()
        let broadcast = HealthEventBroadcast(source)
        let early = await broadcast.subscribe()
        _ = await broadcast.subscribe() // dropped at once: its reader is gone
        let running = Task { await broadcast.run() }
        var reader = early.makeAsyncIterator()
        sink.yield(.prepared)
        #expect(await reader.next() == .prepared)
        let late = await broadcast.subscribe()
        sink.yield(.mirrorConnected)
        sink.finish()
        await running.value
        #expect(await reader.next() == .mirrorConnected)
        #expect(await reader.next() == nil)
        #expect(await Self.all(late) == [.mirrorConnected])
    }

    @Test("When the store's stream ends, so does every subscriber's, and one subscribed later")
    func sourceEnd_endsEverySubscriber() async {
        let (source, sink) = AsyncStream<Event>.makeStream()
        let broadcast = HealthEventBroadcast(source)
        sink.finish()
        await broadcast.run()
        #expect(await Self.all(broadcast.subscribe()).isEmpty)
    }

    @Test("A cancelled run ends the subscribers; a second run returns at once")
    func cancelledRun_endsSubscribers() async {
        let (source, sink) = AsyncStream<Event>.makeStream()
        let broadcast = HealthEventBroadcast(source)
        let subscriber = await broadcast.subscribe()
        let running = Task { await broadcast.run() }
        var reader = subscriber.makeAsyncIterator()
        sink.yield(.prepared)
        #expect(await reader.next() == .prepared) // the first run is taking events
        await broadcast.run()
        running.cancel()
        await running.value
        #expect(await reader.next() == nil)
    }
}
