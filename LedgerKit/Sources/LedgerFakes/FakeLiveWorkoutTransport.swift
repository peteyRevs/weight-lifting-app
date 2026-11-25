#if DEBUG
    import LedgerDomain
    import Synchronization

    /// A phone and a watch joined by one live channel (F17): two `FakeLiveWorkoutTransport`s over a
    /// `FakeLinkBus<WireFrame>`, so every frame between them may be delayed (and so overtaken), lost or duplicated
    /// as the bus's `Link` says, and the pair may be partitioned.
    ///
    /// Deterministic, as the bus is: chance comes from `seed`, and time moves only by `advance(by:)` or `flush()`,
    /// which hand every frame due by then to its transport's `incoming`, in arrival order.
    public final class FakeLiveNetwork: Sendable {
        public typealias Link = FakeLinkBus<WireFrame>.Link

        public let phone: FakeLiveWorkoutTransport
        public let watch: FakeLiveWorkoutTransport
        private let bus: FakeLinkBus<WireFrame>
        private let partitioned = Mutex(false)

        /// Both links start up.
        public init(link: Link = Link(), seed: UInt64) {
            let links = FakeLinkBus<WireFrame>(endpoints: 2, link: link, seed: seed)
            let (phoneEnd, watchEnd) = (links.endpoints[0], links.endpoints[1])
            bus = links
            phone = FakeLiveWorkoutTransport(route: .init(bus: links, from: phoneEnd, recipient: watchEnd))
            watch = FakeLiveWorkoutTransport(route: .init(bus: links, from: watchEnd, recipient: phoneEnd))
        }

        /// How every frame sent from now on travels.
        public func setLink(_ link: Link) {
            bus.setLink(link)
        }

        /// Whether the pair is partitioned now.
        public var isPartitioned: Bool {
            partitioned.withLock { $0 }
        }

        /// Cuts the pair apart: both links report `false`, every send throws `unreachable`, and what was on its way
        /// is lost.
        public func partition() {
            setPartitioned(true)
        }

        /// Joins the pair again: both links report `true`.
        public func heal() {
            setPartitioned(false)
        }

        /// Moves the network's time on by `interval` and hands over every frame due by then.
        public func advance(by interval: Duration) {
            bus.advance(by: interval)
            deliver()
        }

        /// Hands over every frame in flight.
        public func flush() {
            bus.flush()
            deliver()
        }

        private func setPartitioned(_ isPartitioned: Bool) {
            let changed = partitioned.withLock { current in
                defer { current = isPartitioned }
                return current != isPartitioned
            }
            guard changed else {
                return
            }
            if isPartitioned {
                bus.partition(bus.endpoints[0], bus.endpoints[1])
            } else {
                bus.heal(bus.endpoints[0], bus.endpoints[1])
            }
            phone.setReachable(!isPartitioned)
            watch.setReachable(!isPartitioned)
        }

        private func deliver() {
            phone.take(bus.received(by: bus.endpoints[0]).map(\.payload))
            watch.take(bus.received(by: bus.endpoints[1]).map(\.payload))
        }
    }

    /// `LiveWorkoutTransport` for previews and tests (F17). One made by `FakeLiveNetwork` reaches its peer; one made
    /// alone (`init()`, the previews' value) reaches no one: its link is down and every send throws `unreachable`.
    ///
    /// It records what it sent and what it received. With `hang` on, a send waits, announced on `hung`, until it is
    /// cancelled (it then throws `CancellationError` and sends nothing) or `hang` is turned off (it then sends as
    /// usual): a mirrored session's send that never returns (R1 §2.5).
    public final class FakeLiveWorkoutTransport: LiveWorkoutTransport {
        struct Route: Sendable {
            let bus: FakeLinkBus<WireFrame>
            let from: FakeLinkBus<WireFrame>.Endpoint
            let recipient: FakeLinkBus<WireFrame>.Endpoint
        }

        private struct State {
            var isReachable: Bool
            var hang = false
            var sent: [WireFrame] = []
            var received: [WireFrame] = []
            var waiting: [Int: AsyncStream<Never>.Continuation] = [:]
            var nextWait = 0
        }

        public let incoming: AsyncStream<WireFrame>
        public let link: AsyncStream<Bool>
        /// Each frame whose send began to wait because `hang` was on, as it began. One consumer.
        public let hung: AsyncStream<WireFrame>
        /// Each frame as this transport hands it to the network (what `sent` records), as it does. One consumer.
        public let handed: AsyncStream<WireFrame>
        private let incomingSink: AsyncStream<WireFrame>.Continuation
        private let linkSink: AsyncStream<Bool>.Continuation
        private let hungSink: AsyncStream<WireFrame>.Continuation
        private let handedSink: AsyncStream<WireFrame>.Continuation
        private let route: Route?
        private let state: Mutex<State>

        /// A transport that reaches no one.
        public convenience init() {
            self.init(route: nil)
        }

        init(route: Route?) {
            self.route = route
            (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            (link, linkSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            (hung, hungSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            (handed, handedSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            state = Mutex(State(isReachable: route != nil))
            linkSink.yield(route != nil)
        }

        /// Whether a send waits until it is cancelled or this is turned off. Turning it off lets every waiting send
        /// go on.
        public var hang: Bool {
            get { state.withLock { $0.hang } }
            set {
                let released = state.withLock { state in
                    state.hang = newValue
                    guard !newValue else {
                        return [AsyncStream<Never>.Continuation]()
                    }
                    defer { state.waiting = [:] }
                    return Array(state.waiting.values)
                }
                for continuation in released {
                    continuation.finish()
                }
            }
        }

        /// Every frame this transport handed to the network, in order.
        public var sent: [WireFrame] {
            state.withLock { $0.sent }
        }

        /// Every frame the network handed to `incoming`, in order.
        public var received: [WireFrame] {
            state.withLock { $0.received }
        }

        /// How many sends are waiting because of `hang`.
        public var waitingSends: Int {
            state.withLock { $0.waiting.count }
        }

        public func send(_ frame: WireFrame) async throws {
            await waitWhileHung(frame)
            try Task.checkCancellation()
            let destination = try state.withLock { state in
                guard let route, state.isReachable else {
                    throw TransportError.unreachable
                }
                state.sent.append(frame)
                return route
            }
            destination.bus.send(frame, from: destination.from, to: destination.recipient)
            handedSink.yield(frame)
        }

        /// Reports a change of reachability on `link`.
        func setReachable(_ isReachable: Bool) {
            state.withLock { $0.isReachable = isReachable }
            linkSink.yield(isReachable)
        }

        /// Hands to `incoming` the frames of `inbox`, everything the network delivered here so far, that it has not
        /// handed over yet.
        func take(_ inbox: [WireFrame]) {
            let fresh = state.withLock { state in
                defer { state.received = inbox }
                return inbox.dropFirst(state.received.count)
            }
            for frame in fresh {
                incomingSink.yield(frame)
            }
        }

        /// Returns at once without `hang`; with it, when the task is cancelled or `hang` is turned off.
        private func waitWhileHung(_ frame: WireFrame) async {
            let (wait, continuation) = AsyncStream<Never>.makeStream()
            let ticket = state.withLock { state -> Int? in
                guard state.hang else {
                    return nil
                }
                defer { state.nextWait += 1 }
                state.waiting[state.nextWait] = continuation
                return state.nextWait
            }
            guard let ticket else {
                return
            }
            hungSink.yield(frame)
            for await _ in wait {}
            state.withLock { _ = $0.waiting.removeValue(forKey: ticket) }
        }
    }
#endif
