#if DEBUG
    import Foundation
    import LedgerDomain
    import Synchronization

    /// A phone and a watch joined by WatchConnectivity's queued calls, in memory (F19): two `FakeCompanionTransport`s
    /// whose payloads reach each other as `CompanionCodec` bytes would, so a payload the codec refuses is refused here
    /// too, and what arrives is the decoded copy.
    ///
    /// Deterministic, with no clock: while connected, a payload is on the peer's stream when its call returns; while
    /// disconnected, payloads wait, and `connect()` hands over the latest context of each direction alone (an
    /// application context replaces the one before it), then every record and file in the order sent.
    public final class FakeCompanionNetwork: Sendable {
        public let phone: FakeCompanionTransport
        public let watch: FakeCompanionTransport
        private let hub: CompanionHub

        /// A paired phone and watch, connected, with the watch app installed unless `isWatchAppInstalled` is false.
        public init(isWatchAppInstalled: Bool = true) {
            hub = CompanionHub(isPaired: true, isAvailable: isWatchAppInstalled, isConnected: true)
            phone = FakeCompanionTransport(hub: hub, end: .phone)
            watch = FakeCompanionTransport(hub: hub, end: .watch)
        }

        /// Whether payloads reach the peer now.
        public var isConnected: Bool {
            hub.withState(\.isConnected)
        }

        /// The devices go out of reach: payloads sent from now on wait for `connect()`.
        public func disconnect() {
            hub.setConnected(false)
        }

        /// The devices come back in reach: every waiting payload arrives.
        public func connect() {
            hub.setConnected(true)
        }

        /// Installs or removes the watch app: while it is removed, every send throws
        /// `CompanionTransportError.unavailable` and both transports read `isWatchAppInstalled` as false.
        public func setWatchAppInstalled(_ isInstalled: Bool) {
            hub.setAvailable(isInstalled)
        }
    }

    /// `CompanionTransport` for previews and tests (F19). One made by `FakeCompanionNetwork` reaches its peer; one
    /// made alone (`init()`, the previews' value) reaches no one: it reads as unpaired and every send throws
    /// `CompanionTransportError.unavailable`.
    ///
    /// It records every payload it took, in call order, as the peer receives it.
    public final class FakeCompanionTransport: CompanionTransport {
        public let receivedContext: AsyncStream<CompanionContext>
        public let receivedFiles: AsyncStream<CompanionFile>
        public let receivedRecords: AsyncStream<FinishedWorkoutRecord>
        private let hub: CompanionHub
        private let end: CompanionHub.End

        /// A transport that reaches no one.
        public convenience init() {
            self.init(hub: CompanionHub(isPaired: false, isAvailable: false, isConnected: false), end: .phone)
        }

        init(hub: CompanionHub, end: CompanionHub.End) {
            self.hub = hub
            self.end = end
            let mailbox = hub.mailboxes[end.rawValue]
            (receivedContext, receivedFiles, receivedRecords) = (mailbox.contexts, mailbox.files, mailbox.records)
        }

        /// Every context it took, in order.
        public var sentContexts: [CompanionContext] {
            hub.withState { $0.sentContexts[end.rawValue] }
        }

        /// Every file it took, in order.
        public var sentFiles: [CompanionFile] {
            hub.withState { $0.sentFiles[end.rawValue] }
        }

        /// Every record it took as user info, in order.
        public var sentRecords: [FinishedWorkoutRecord] {
            hub.withState { $0.sentRecords[end.rawValue] }
        }

        public var isPaired: Bool {
            hub.isPaired
        }

        public var isWatchAppInstalled: Bool {
            hub.withState(\.isAvailable)
        }

        public func updateContext(_ context: CompanionContext) async throws {
            try hub.send(.context(Self.roundTrip(context)), from: end)
        }

        public func transfer(_ file: CompanionFile) async throws {
            try hub.send(.file(Self.roundTrip(file)), from: end)
        }

        public func enqueue(_ record: FinishedWorkoutRecord) async throws {
            guard try CompanionCodec.delivery(for: record) == .userInfo else {
                throw CompanionCodecError.tooLarge
            }
            try hub.send(.record(Self.roundTrip(record)), from: end)
        }

        /// `payload` as the peer decodes it from the bytes it would be sent as.
        private static func roundTrip<Payload: CompanionPayload>(_ payload: Payload) throws -> Payload {
            try CompanionCodec.decode(Payload.self, from: CompanionCodec.encode(payload))
        }
    }

    /// What joins a `FakeCompanionNetwork`'s two ends: their mailboxes, what each sent, and what waits.
    final class CompanionHub: Sendable {
        enum End: Int, Sendable {
            case phone, watch

            var peer: End {
                self == .phone ? .watch : .phone
            }
        }

        enum Payload: Sendable {
            case context(CompanionContext)
            case file(CompanionFile)
            case record(FinishedWorkoutRecord)
        }

        /// One end's three streams, and what feeds them.
        struct Mailbox: Sendable {
            let contexts: AsyncStream<CompanionContext>
            let files: AsyncStream<CompanionFile>
            let records: AsyncStream<FinishedWorkoutRecord>
            private let contextSink: AsyncStream<CompanionContext>.Continuation
            private let fileSink: AsyncStream<CompanionFile>.Continuation
            private let recordSink: AsyncStream<FinishedWorkoutRecord>.Continuation

            init() {
                let context = AsyncStream.makeStream(of: CompanionContext.self, bufferingPolicy: .unbounded)
                let file = AsyncStream.makeStream(of: CompanionFile.self, bufferingPolicy: .unbounded)
                let record = AsyncStream.makeStream(of: FinishedWorkoutRecord.self, bufferingPolicy: .unbounded)
                (contexts, files, records) = (context.stream, file.stream, record.stream)
                (contextSink, fileSink, recordSink) = (context.continuation, file.continuation, record.continuation)
            }

            func take(_ payload: Payload) {
                switch payload {
                case let .context(context): contextSink.yield(context)
                case let .file(file): fileSink.yield(file)
                case let .record(record): recordSink.yield(record)
                }
            }
        }

        /// Each array is by `End.rawValue`: of the sender for what was sent, of the recipient for what waits.
        struct State {
            var isAvailable: Bool
            var isConnected: Bool
            var sentContexts: [[CompanionContext]] = [[], []]
            var sentFiles: [[CompanionFile]] = [[], []]
            var sentRecords: [[FinishedWorkoutRecord]] = [[], []]
            var waitingContext: [CompanionContext?] = [nil, nil]
            var waiting: [[Payload]] = [[], []]
        }

        /// Whether the two ends are a pair: a lone transport's hub is not.
        let isPaired: Bool
        let mailboxes = [Mailbox(), Mailbox()]
        private let state: Mutex<State>

        init(isPaired: Bool, isAvailable: Bool, isConnected: Bool) {
            self.isPaired = isPaired
            state = Mutex(State(isAvailable: isAvailable, isConnected: isConnected))
        }

        func withState<Value: Sendable>(_ read: (State) -> Value) -> Value {
            state.withLock { read($0) }
        }

        func setAvailable(_ isAvailable: Bool) {
            state.withLock { $0.isAvailable = isAvailable }
        }

        /// Records `payload` and hands it to the peer's mailbox, or keeps it for `setConnected(true)`. Throws
        /// `unavailable`, recording nothing, while the peer app is not installed.
        func send(_ payload: Payload, from end: End) throws {
            try state.withLock { state in
                guard state.isAvailable else {
                    throw CompanionTransportError.unavailable
                }
                let peer = end.peer.rawValue
                switch payload {
                case let .context(context):
                    state.sentContexts[end.rawValue].append(context)
                    if !state.isConnected {
                        state.waitingContext[peer] = context
                        return
                    }
                case let .file(file): state.sentFiles[end.rawValue].append(file)
                case let .record(record): state.sentRecords[end.rawValue].append(record)
                }
                if state.isConnected {
                    mailboxes[peer].take(payload)
                } else {
                    state.waiting[peer].append(payload)
                }
            }
        }

        /// Connecting hands each end the latest context that waits for it, then the rest, in the order sent.
        func setConnected(_ isConnected: Bool) {
            state.withLock { state in
                state.isConnected = isConnected
                guard isConnected else {
                    return
                }
                for (mailbox, (context, waiting)) in zip(mailboxes, zip(state.waitingContext, state.waiting)) {
                    for payload in (context.map { [.context($0)] } ?? []) + waiting {
                        mailbox.take(payload)
                    }
                }
                (state.waitingContext, state.waiting) = ([nil, nil], [[], []])
            }
        }
    }
#endif
