import Foundation
import LedgerDomain
import os

/// The live transport (F17 S4; ADR-005 §3): the host sends its own envelopes as it stores them, answers the
/// peer's frames, and on every link-up sends a handshake, so whatever either side missed (a lost frame, a
/// partition, a receive that failed) is replayed from the other's store.
public extension LocalWorkoutSessionActor {
    /// How long one send may take before the host gives up on it (a mirrored send can hang, R1 §2.5).
    static let sendTimeout = Duration.seconds(3)
    /// The least time between two handshakes or replay requests for one workout that a peer's frame triggers.
    static let handshakeInterval: TimeInterval = 10

    /// Connects the host to the peer over `transport`, once, for the host's life:
    /// - every envelope this host stores of its own is sent as it is stored, in order, by a sender of its own:
    ///   no call waits on it. A send that fails is logged and not retried; one that takes longer than
    ///   `sendTimeout` (on `clock`) is cancelled. The next handshake replays either;
    /// - every frame that arrives is taken as `receive(_:)` takes it, its failures logged;
    /// - every time the link comes up (and when it is up at once) the host sends a handshake for each workout its
    ///   store holds a log of, live, ended and not yet saved, or waiting for its `started`.
    ///
    /// Returns once the transport's first link state is taken (its handshakes sent, when it is up), so a call made
    /// after `connect` never races the first handshake.
    func connect(_ transport: any LiveWorkoutTransport, clock: any Clock<Duration> = ContinuousClock()) async {
        guard connection.outbox == nil else {
            logger.fault("The session host was connected to a second transport; ignored")
            return
        }
        let (frames, sink) = AsyncStream<WireFrame>.makeStream(bufferingPolicy: .unbounded)
        let (firstLink, firstLinkSink) = AsyncStream<Never>.makeStream()
        connection.outbox = sink
        let logger = logger
        connection.links = [
            Task {
                for await frame in frames {
                    await Self.send(frame, over: transport, clock: clock, logger: logger)
                }
            },
            Task { [weak self] in
                for await frame in transport.incoming {
                    await self?.deliver(frame)
                }
            },
            Task { [weak self] in
                for await isUp in transport.link {
                    if isUp {
                        await self?.linkCameUp()
                    }
                    firstLinkSink.finish()
                }
                firstLinkSink.finish()
            }
        ]
        for await _ in firstLink {}
    }

    /// Takes one frame from the peer:
    /// - `.envelopes` as `receive(_ envelopes:)` does. When that throws, the host asks the peer to send the
    ///   workouts again (`.replayRequest`, at most once per `handshakeInterval`), and throws;
    /// - `.handshake`: replies with every envelope of the workout's log that the peer's vector does not cover,
    ///   this device's and relayed ones alike, then with its own handshake unless it sent one in the last
    ///   `handshakeInterval`;
    /// - `.replayRequest`: replies with what the vector does not cover, and nothing more.
    ///
    /// Before a transport is connected the replies go nowhere.
    func receive(_ frame: WireFrame) async throws {
        switch frame {
        case let .envelopes(envelopes):
            do {
                try await receive(envelopes)
            } catch {
                let workouts = envelopes.reduce(into: [WorkoutID]()) { workouts, envelope in
                    if !workouts.contains(envelope.workoutID) {
                        workouts.append(envelope.workoutID)
                    }
                }
                try? await inTurn {
                    try await self.askAgain(for: workouts)
                } // logged inside; the error thrown is the receipt's
                throw error
            }
        case let .handshake(workout, vector):
            try await inTurn { try await self.answer(workout, vector, withHandshake: true) }
        case let .replayRequest(workout, vector):
            try await inTurn { try await self.answer(workout, vector, withHandshake: false) }
        }
    }
}

extension LocalWorkoutSessionActor {
    /// What the host keeps of its transport.
    struct Connection {
        /// Where frames for the peer wait for the sender.
        var outbox: AsyncStream<WireFrame>.Continuation?
        /// The sender and the two listeners, cancelled with the host.
        var links: [Task<Void, Never>] = []
        /// When the host last sent a handshake or a replay request for each workout (`handshakeInterval`).
        var lastAsked: [WorkoutID: Date] = [:]
    }

    /// Hands the envelopes of `effects`' `.transmit` to the sender. Run once each own envelope is stored.
    func transmit(_ effects: [Effect]) {
        for case let .transmit(envelope) in effects {
            connection.outbox?.yield(.envelopes([envelope]))
        }
    }

    /// For each workout this store holds a log of, the highest `n` such that it holds `1 ... n` of each device:
    /// what a handshake carries (`WireFrame.handshake`).
    func contiguousSeq(of workout: WorkoutID) async throws -> [DeviceID: UInt64] {
        let keys = try await Set(events.envelopes(for: workout).map(\.key))
        var vector: [DeviceID: UInt64] = [:]
        for device in Set(keys.map(\.device)) {
            var held: UInt64 = 0
            while keys.contains(EnvelopeKey(device: device, seq: held + 1)) {
                held += 1
            }
            if held > 0 {
                vector[device] = held
            }
        }
        return vector
    }

    /// The link-up handshakes, in turn, after recovery: the launch's resume is covered too. A link-up starts the
    /// rate limit afresh: what this host asked for before the link went down may have been lost with it, and a
    /// workout only the peer holds is learned only by asking (F17 S5b; the double-start property found a watch
    /// that never learned the phone's workout because its one request had been lost seconds before).
    private func linkCameUp() async {
        do {
            try await inTurn {
                await self.forgetAsked()
                try await self.ready()
                for workout in try await self.events.uncompactedWorkoutIDs() {
                    try await self.handshake(for: workout)
                }
            }
        } catch {
            logger.error("No handshake on link-up: \(String(describing: error))")
        }
    }

    /// Clears the rate limit's memory (`handshakeInterval`).
    private func forgetAsked() {
        connection.lastAsked = [:]
    }

    /// A frame from the transport's listener: errors are the host's to log, not the transport's.
    private func deliver(_ frame: WireFrame) async {
        do {
            try await receive(frame)
        } catch {
            logger.error("A received frame was not taken: \(String(describing: error))")
        }
    }

    /// The reply to a handshake or a replay request.
    private func answer(_ workout: WorkoutID, _ vector: [DeviceID: UInt64], withHandshake: Bool) async throws {
        try await ready()
        let missing = try await events.envelopes(for: workout).filter { $0.seq > vector[$0.device] ?? 0 }
        if !missing.isEmpty {
            connection.outbox?.yield(.envelopes(missing.sorted()))
        }
        if withHandshake, isDue(workout) {
            try await handshake(for: workout)
        }
    }

    /// Replay requests for workouts a receipt failed to store, each at most once per `handshakeInterval`.
    private func askAgain(for workouts: [WorkoutID]) async throws {
        for workout in workouts where isDue(workout) {
            do {
                let vector = try await contiguousSeq(of: workout)
                connection.lastAsked[workout] = now()
                connection.outbox?.yield(.replayRequest(workoutID: workout, contiguousSeq: vector))
            } catch {
                logger.error("No replay request after a failed receipt: \(String(describing: error))")
                throw error
            }
        }
    }

    /// Sends this store's vector for `workout`.
    private func handshake(for workout: WorkoutID) async throws {
        let vector = try await contiguousSeq(of: workout)
        connection.lastAsked[workout] = now()
        connection.outbox?.yield(.handshake(workoutID: workout, contiguousSeq: vector))
    }

    /// Whether `handshakeInterval` has passed since the host last asked the peer about `workout`.
    private func isDue(_ workout: WorkoutID) -> Bool {
        guard let last = connection.lastAsked[workout] else {
            return true
        }
        return !(now().timeIntervalSince(last) < Self.handshakeInterval)
    }

    /// One send, raced against `sendTimeout`. The transport's send returns when cancelled
    /// (`LiveWorkoutTransport.send`), so the race ends with the timeout.
    private static func send(
        _ frame: WireFrame,
        over transport: any LiveWorkoutTransport,
        clock: any Clock<Duration>,
        logger: Logger
    ) async {
        let timeout = sendTimeout
        let failure = await withTaskGroup(of: (any Error)?.self) { group in
            group.addTask {
                do {
                    try await transport.send(frame)
                    return nil
                } catch {
                    return error
                }
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                    return TransportError.timeout
                } catch {
                    return nil // cancelled: the send answered first
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let failure {
            logger.notice("A frame was not sent: \(String(describing: failure), privacy: .public)")
        }
    }
}
