#if DEBUG
    import Synchronization

    /// An in-memory network of `endpoints` devices for sync tests (F07 criterion 5): every message between two
    /// endpoints may be delayed, lost or duplicated, and a pair may be partitioned. It knows no transport
    /// protocol (F17 owns that, and builds `FakeLiveWorkoutTransport` over it), only payloads.
    ///
    /// Deterministic: chance comes from a generator seeded by `seed`, and time is the bus's own, moved by
    /// `advance(by:)` or `flush()`, never the wall clock. The same seed, link and calls deliver the same
    /// messages at the same times, in the same order.
    public final class FakeLinkBus<Payload: Sendable>: Sendable {
        /// One device on the bus.
        public struct Endpoint: Hashable, Sendable, Comparable {
            public let index: Int

            public static func < (lhs: Endpoint, rhs: Endpoint) -> Bool {
                lhs.index < rhs.index
            }
        }

        /// How every message travels: its delay, drawn uniformly from `delay`, the chance `loss` that it is
        /// lost, and the chance `duplication` that it arrives twice (each copy with its own delay). The default
        /// is instant, lossless and exactly once. A delay lies in `0 … Int64.max` nanoseconds (about 292 years):
        /// a bus given another traps (`precondition`), as a negative delay would deliver a message before it
        /// was sent.
        public struct Link: Sendable {
            public var delay: ClosedRange<Duration>
            public var loss: Double
            public var duplication: Double

            public init(delay: ClosedRange<Duration> = .zero ... .zero, loss: Double = 0, duplication: Double = 0) {
                self.delay = delay
                self.loss = loss
                self.duplication = duplication
            }
        }

        /// A message as an endpoint received it, at the bus's time `arrival`.
        public struct Delivery: Sendable {
            public let from: Endpoint
            public let payload: Payload
            public let arrival: Duration
        }

        private struct InFlight {
            let arrival: Duration
            let order: Int
            let from: Endpoint
            let recipient: Endpoint
            let payload: Payload
        }

        private struct State {
            var random: SplitMix64
            var link: Link
            var now: Duration = .zero
            var sent = 0
            var inFlight: [InFlight] = []
            var inboxes: [Endpoint: [Delivery]] = [:]
            var partitions: Set<Set<Endpoint>> = []
        }

        public let endpoints: [Endpoint]
        private let state: Mutex<State>

        public init(endpoints count: Int, link: Link = Link(), seed: UInt64) {
            Self.requireValid(link)
            endpoints = (0 ..< max(0, count)).map(Endpoint.init)
            state = Mutex(State(random: SplitMix64(seed: seed), link: link))
        }

        /// The link every message sent from now on travels.
        public func setLink(_ link: Link) {
            Self.requireValid(link)
            state.withLock { $0.link = link }
        }

        /// Sends `payload` from one endpoint to another: lost now with the link's `loss`, or scheduled to
        /// arrive after the link's delay (twice with its `duplication`). Nothing crosses a partition, and
        /// nothing goes from or to an endpoint this bus did not make (one of another, larger bus): it is
        /// dropped, as a message to a device that is not on the network.
        public func send(_ payload: Payload, from: Endpoint, to recipient: Endpoint) {
            guard isOnBus(from), isOnBus(recipient) else {
                return
            }
            state.withLock { state in
                guard !state.partitions.contains([from, recipient]) else {
                    return
                }
                guard Double.random(in: 0 ..< 1, using: &state.random) >= state.link.loss else {
                    return
                }
                let copies = Double.random(in: 0 ..< 1, using: &state.random) < state.link.duplication ? 2 : 1
                for _ in 0 ..< copies {
                    let delay = Self.duration(in: state.link.delay, using: &state.random)
                    let message = InFlight(
                        arrival: state.now + delay,
                        order: state.sent,
                        from: from,
                        recipient: recipient,
                        payload: payload
                    )
                    state.inFlight.append(message)
                    state.sent += 1
                }
            }
        }

        /// Sends `payload` from `from` to every other endpoint.
        public func broadcast(_ payload: Payload, from: Endpoint) {
            for endpoint in endpoints where endpoint != from {
                send(payload, from: from, to: endpoint)
            }
        }

        /// Cuts the link between `first` and `second`: what is sent across it, or arrives across it, is lost.
        public func partition(_ first: Endpoint, _ second: Endpoint) {
            state.withLock { _ = $0.partitions.insert([first, second]) }
        }

        /// Restores the link between `first` and `second`.
        public func heal(_ first: Endpoint, _ second: Endpoint) {
            state.withLock { _ = $0.partitions.remove([first, second]) }
        }

        /// Moves the bus's time on by `interval`, delivering every message due by then, by arrival time and
        /// then in the order sent. Time never moves back: a negative interval moves it by nothing, so arrivals
        /// stay in order.
        public func advance(by interval: Duration) {
            state.withLock { state in
                state.now += max(interval, .zero)
                Self.deliver(upTo: state.now, in: &state)
            }
        }

        /// Delivers every message in flight, moving the bus's time to the last arrival.
        public func flush() {
            state.withLock { state in
                state.now = max(state.now, state.inFlight.map(\.arrival).max() ?? state.now)
                Self.deliver(upTo: state.now, in: &state)
            }
        }

        /// What `endpoint` has received so far, in arrival order.
        public func received(by endpoint: Endpoint) -> [Delivery] {
            state.withLock { $0.inboxes[endpoint] ?? [] }
        }

        /// How many messages are still travelling.
        public var inFlightCount: Int {
            state.withLock { $0.inFlight.count }
        }

        private static func deliver(upTo time: Duration, in state: inout State) {
            let due = state.inFlight.filter { $0.arrival <= time }.sorted { lhs, rhs in
                (lhs.arrival, lhs.order) < (rhs.arrival, rhs.order)
            }
            state.inFlight.removeAll { $0.arrival <= time }
            for message in due where !state.partitions.contains([message.from, message.recipient]) {
                let delivery = Delivery(from: message.from, payload: message.payload, arrival: message.arrival)
                state.inboxes[message.recipient, default: []].append(delivery)
            }
        }

        /// Whether `endpoint` is one of this bus's.
        private func isOnBus(_ endpoint: Endpoint) -> Bool {
            endpoints.indices.contains(endpoint.index)
        }

        /// Traps on a delay outside `0 … Int64.max` nanoseconds (`Link`).
        private static func requireValid(_ link: Link) {
            precondition(
                link.delay.lowerBound >= .zero && link.delay.upperBound <= .nanoseconds(Int64.max),
                "FakeLinkBus: a delay lies in 0 … Int64.max nanoseconds, not \(link.delay)"
            )
        }

        /// A duration drawn uniformly from `range`, to the nanosecond (`requireValid` keeps it within `Int64`).
        private static func duration(in range: ClosedRange<Duration>, using random: inout SplitMix64) -> Duration {
            let span = (range.upperBound - range.lowerBound) / .nanoseconds(1)
            let drawn = min(Double.random(in: 0 ... 1, using: &random) * span, Double(Int64.max).nextDown)
            return range.lowerBound + .nanoseconds(Int64(drawn))
        }
    }
#endif
