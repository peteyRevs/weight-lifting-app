import Foundation
import LedgerDomain
import os

/// The live transport over HealthKit's mirrored session (F17 S6; ADR-005 §2, §4; R1 §2.5), reached only through
/// F16's `RemoteSessionChannel`:
/// - **Nothing goes before the channel is up.** F16 reports `connection` true only once the session is prepared
///   and mirroring has started (the watch), or a mirrored session was handed over (the phone), so a send while it
///   is down throws `unreachable` and nothing is kept for later: the next handshake replays it.
/// - **Batching:** frames handed within `batchWindow` (150 ms) of the first go out together, the envelopes of
///   neighbouring frames as one `.envelopes` frame, cut by `WireCodec`. `send` returns once a frame is queued, so
///   the host's serial sender can hand the next one inside the window.
/// - **The handshake first** after each time the channel comes up: the first handshake queued goes to the front
///   of that batch; when none was queued, an empty one for the batch's first workout leads it, which only asks
///   the peer to send what it holds of that workout (it then answers with its own handshake).
/// - **The watchdog:** each channel send is given `watchdog` (3 s). One that does not answer by then is left
///   hanging (it may never return, even when cancelled, R1 §2.5 #2) and the transport is `degraded`: it sends
///   nothing more on the channel for the workouts it knew of then, and stays degraded until a frame of a workout
///   it had never seen is handed to it, a new workout on a new session.
/// - **One retry** on a send that fails with `HealthError.underlying`: "remote session delegate is not set up"
///   (R1 §2.5 #3) has no case of its own, and its code is to be pinned on device (F20; notes, item 12).
///
/// `run()` reads the channel and sends the batches; the owner runs it for the transport's life.
public actor MirroringTransport: LiveWorkoutTransport {
    /// How long the transport collects frames before it sends them.
    public static let batchWindow = Duration.milliseconds(150)
    /// How long one channel send may take before the transport counts it as hung.
    public static let watchdog = Duration.seconds(3)

    /// What the transport can do now.
    public enum Status: Hashable, Sendable {
        /// The channel is down: sends throw `unreachable`.
        case down
        /// The channel is up and sends go out on it.
        case open
        /// A send hung: nothing more goes on the channel for the workouts the transport knew of then.
        case degraded
    }

    public nonisolated let incoming: AsyncStream<WireFrame>
    /// `true` each time the channel comes up (so also twice in a row, when the phone is handed a new mirrored
    /// session), `false` when it drops or the transport is degraded. Starts `false`. One consumer.
    public nonisolated let link: AsyncStream<Bool>
    /// The status when made (`down`), then after each change of the channel's connection and each degradation, as
    /// `link`. One consumer: `CompositeTransport`.
    public nonisolated let status: AsyncStream<Status>

    private let channel: any RemoteSessionChannel
    private let clock: any Clock<Duration>
    private let incomingSink: AsyncStream<WireFrame>.Continuation
    private let linkSink: AsyncStream<Bool>.Continuation
    private let statusSink: AsyncStream<Status>.Continuation
    /// One element each time a batch is begun: the sender waits out the window, then sends it.
    private let batches: AsyncStream<Void>
    private let batchesSink: AsyncStream<Void>.Continuation
    private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "sync")

    private var isConnected = false
    private var isRunning = false
    /// Frames waiting for the window to end, in the order handed.
    private var queued: [WireFrame] = []
    private var isBatchBegun = false
    /// Whether the next batch must lead with a handshake: the channel came up since the last one.
    private var needsHandshake = false
    /// Every workout a frame was handed for.
    private var known: Set<WorkoutID> = []
    /// The workouts known when a send hung; nil while no send has hung (or since a new workout began).
    private var stuck: Set<WorkoutID>?
    /// Sends past the watchdog, cancelled when `run()` ends: they may still answer.
    private var hung: [Task<Void, Never>] = []

    public init(channel: any RemoteSessionChannel, clock: any Clock<Duration> = ContinuousClock()) {
        self.channel = channel
        self.clock = clock
        (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (link, linkSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (status, statusSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (batches, batchesSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        linkSink.yield(false)
        statusSink.yield(.down)
    }

    /// Queues `frame` for the next batch. Throws `unreachable` while the channel is down, or when the transport is
    /// degraded for the frame's workout.
    public func send(_ frame: WireFrame) async throws {
        let workouts = frame.workoutIDs
        if let stuck, !workouts.isEmpty, stuck.isDisjoint(with: workouts) {
            self.stuck = nil
            logger.notice("Mirroring is tried again for a new workout")
            report()
        }
        known.formUnion(workouts)
        guard isConnected, stuck == nil else {
            throw TransportError.unreachable
        }
        queued.append(frame)
        if !isBatchBegun {
            isBatchBegun = true
            batchesSink.yield()
        }
    }

    /// Reads the channel and sends each batch, until the caller's task is cancelled (or the channel's streams
    /// end); then ends `incoming`, `link` and `status`. Runs once: a second call returns at once.
    public func run() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await isUp in self.channel.connection {
                    await self.connectionChanged(isUp)
                }
            }
            group.addTask {
                for await batch in self.channel.incoming {
                    batch.forEach(self.take)
                }
            }
            group.addTask {
                for await _ in self.batches {
                    do {
                        try await self.clock.sleep(for: Self.batchWindow)
                    } catch {
                        return
                    }
                    await self.sendBatch()
                }
            }
            await group.next()
            group.cancelAll()
        }
        hung.forEach { $0.cancel() }
        hung = []
        incomingSink.finish()
        linkSink.finish()
        statusSink.finish()
    }

    /// One frame from the peer onto `incoming`; one that cannot be read is dropped, and the next handshake
    /// replays what it held.
    private nonisolated func take(_ data: Data) {
        do {
            try incomingSink.yield(WireCodec.decode(data))
        } catch {
            logger.notice("A mirrored frame was not read: \(String(describing: error), privacy: .public)")
        }
    }

    private func connectionChanged(_ isUp: Bool) {
        isConnected = isUp
        if isUp {
            needsHandshake = true
        } else {
            queued = [] // lost with the link; the next handshake replays it
        }
        report()
    }

    private func report() {
        let now: Status = stuck != nil ? .degraded : isConnected ? .open : .down
        statusSink.yield(now)
        linkSink.yield(now == .open)
    }
}

extension MirroringTransport {
    /// Sends what was queued in the window, the handshake first when the channel came up since the last batch.
    private func sendBatch() async {
        var frames = queued
        queued = []
        isBatchBegun = false
        guard isConnected, stuck == nil, let first = frames.first else {
            return
        }
        if needsHandshake {
            needsHandshake = false
            if let handshake = frames.firstIndex(where: \.isHandshake) {
                frames.insert(frames.remove(at: handshake), at: 0)
            } else if let workout = first.workoutIDs.first {
                frames.insert(.handshake(workoutID: workout, contiguousSeq: [:]), at: 0)
            }
        }
        for frame in Self.joined(frames) {
            let parts: [Data]
            do {
                parts = try WireCodec.encode(frame)
            } catch {
                logger.error("A frame was not encoded: \(String(describing: error), privacy: .public)")
                continue
            }
            for data in parts {
                guard isConnected, stuck == nil, !Task.isCancelled else {
                    return // the rest is replayed by the next handshake
                }
                await sendWithRetry(data)
            }
        }
    }

    /// One channel send, and one more after an `underlying` failure; a hang degrades the transport.
    private func sendWithRetry(_ data: Data) async {
        for attempt in 1 ... 2 {
            switch await watched(data) {
            case .sent:
                return
            case let .failed(HealthError.underlying(code)) where attempt == 1:
                logger.notice("A mirrored send failed (code \(code, privacy: .public)); trying once more")
            case let .failed(error):
                logger.notice("A mirrored send failed: \(String(describing: error), privacy: .public)")
                return
            case .hung:
                logger.error("A mirrored send hung; mirroring is degraded for this workout")
                stuck = known
                queued = []
                report()
                return
            }
        }
    }

    private enum Answer: Sendable {
        case sent
        case failed(any Error)
        case hung
    }

    /// `data` sent on the channel, or `hung` past `watchdog`. The send runs as a task of its own, which the race
    /// does not wait for: a hung one is kept in `hung` until `run()` ends.
    private func watched(_ data: Data) async -> Answer {
        let (answers, sink) = AsyncStream<Answer>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let sending = Task {
            do {
                try await self.channel.send(data)
                sink.yield(.sent)
            } catch {
                sink.yield(.failed(error))
            }
        }
        let answer = await withTaskGroup(of: Answer?.self) { group in
            group.addTask {
                for await answer in answers {
                    return answer
                }
                return nil // cancelled: the watchdog went first
            }
            group.addTask {
                do {
                    try await self.clock.sleep(for: Self.watchdog)
                    return .hung
                } catch {
                    return nil // cancelled: the send answered first
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .hung
        }
        if case .hung = answer {
            hung.append(sending)
        }
        return answer
    }

    /// `frames` with the envelopes of neighbouring `.envelopes` frames joined into one frame.
    private static func joined(_ frames: [WireFrame]) -> [WireFrame] {
        frames.reduce(into: []) { joined, frame in
            if case let .envelopes(more) = frame, case let .envelopes(some)? = joined.last {
                joined[joined.count - 1] = .envelopes(some + more)
            } else {
                joined.append(frame)
            }
        }
    }
}

extension WireFrame {
    /// The workouts the frame is about.
    var workoutIDs: [WorkoutID] {
        switch self {
        case let .envelopes(envelopes):
            envelopes.reduce(into: []) { workouts, envelope in
                if !workouts.contains(envelope.workoutID) {
                    workouts.append(envelope.workoutID)
                }
            }
        case let .handshake(workout, _), let .replayRequest(workout, _):
            [workout]
        }
    }

    var isHandshake: Bool {
        if case .handshake = self {
            return true
        }
        return false
    }
}
