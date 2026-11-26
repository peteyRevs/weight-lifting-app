import Foundation
import LedgerDomain

/// The live transport the session host is connected to (F17 S6; ADR-005 §3): every frame goes out on both the
/// mirrored session and WatchConnectivity, and what either brings in arrives on one `incoming`. The host dedupes by
/// `(device, seq)`, so a frame that comes on both is stored once.
///
/// - `link` is `true` each time either channel comes up, so the host's handshake goes out on each (on mirroring it
///   must lead, `MirroringTransport`), and `false` when neither reaches the peer.
/// - `connection` is what the workout screen shows (criterion 12): `.connected(.mirroring)` while mirroring is up;
///   else, while WatchConnectivity reaches the peer, `.degraded(.mirroring)` when mirroring hung and
///   `.connected(.watchConnectivity)` otherwise; else `.reconnecting` for `reconnectWindow` (30 s) after the peer
///   was last reached; else `.solo`.
///
/// `run()` runs the mirroring transport and reads both channels; the owner runs it for the transport's life.
public actor CompositeTransport: LiveWorkoutTransport {
    /// How long after the peer dropped out of reach the screen says it is reconnecting.
    public static let reconnectWindow = Duration.seconds(30)

    public nonisolated let incoming: AsyncStream<WireFrame>
    public nonisolated let link: AsyncStream<Bool>
    /// The state when made (`.solo`), then each change. One consumer.
    public nonisolated let connection: AsyncStream<LiveConnectionState>

    private let mirroring: MirroringTransport
    private let watchConnectivity: any LiveWorkoutTransport
    private let clock: any Clock<Duration>
    private let incomingSink: AsyncStream<WireFrame>.Continuation
    private let linkSink: AsyncStream<Bool>.Continuation
    private let connectionSink: AsyncStream<LiveConnectionState>.Continuation

    private var isRunning = false
    private var mirroringStatus = MirroringTransport.Status.down
    private var isWatchConnectivityUp = false
    private var isReconnecting = false
    private var shown = LiveConnectionState.solo
    /// Ends the reconnect window; cancelled when the peer is reached again, or when `run()` ends.
    private var windowEnd: Task<Void, Never>?
    /// Which drop the open window is for, so a window that ended late closes no later one.
    private var drops = 0

    public init(
        mirroring: MirroringTransport,
        watchConnectivity: any LiveWorkoutTransport,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.mirroring = mirroring
        self.watchConnectivity = watchConnectivity
        self.clock = clock
        (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (link, linkSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (connection, connectionSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        linkSink.yield(false)
        connectionSink.yield(.solo)
    }

    /// Sends `frame` on both channels at once. Returns when both answered and either took it; otherwise throws
    /// mirroring's error.
    public func send(_ frame: WireFrame) async throws {
        async let onMirroring = Self.result { try await self.mirroring.send(frame) }
        async let onWatchConnectivity = Self.result { try await self.watchConnectivity.send(frame) }
        let (mirrored, boosted) = await (onMirroring, onWatchConnectivity)
        if case .success = boosted {
            return
        }
        try mirrored.get()
    }

    /// Runs the mirroring transport and reads both channels, until the caller's task is cancelled; then ends
    /// `incoming`, `link` and `connection`. Runs once: a second call returns at once.
    public func run() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.mirroring.run() }
            group.addTask {
                for await status in self.mirroring.status {
                    await self.mirroringChanged(status)
                }
            }
            group.addTask {
                for await isUp in self.watchConnectivity.link {
                    await self.watchConnectivityChanged(isUp)
                }
            }
            group.addTask {
                for await frame in self.mirroring.incoming {
                    self.incomingSink.yield(frame)
                }
            }
            group.addTask {
                for await frame in self.watchConnectivity.incoming {
                    self.incomingSink.yield(frame)
                }
            }
        }
        windowEnd?.cancel()
        incomingSink.finish()
        linkSink.finish()
        connectionSink.finish()
    }

    private var isReachable: Bool {
        mirroringStatus == .open || isWatchConnectivityUp
    }

    private func mirroringChanged(_ changed: MirroringTransport.Status) {
        let wasReachable = isReachable
        mirroringStatus = changed
        reached(cameUp: changed == .open, wasReachable: wasReachable)
    }

    private func watchConnectivityChanged(_ isUp: Bool) {
        let wasReachable = isReachable
        let cameUp = isUp && !isWatchConnectivityUp
        isWatchConnectivityUp = isUp
        reached(cameUp: cameUp, wasReachable: wasReachable)
    }

    /// After a channel's change: the link, the reconnect window and what the screen shows.
    private func reached(cameUp: Bool, wasReachable: Bool) {
        if cameUp {
            linkSink.yield(true)
        } else if wasReachable, !isReachable {
            linkSink.yield(false)
        }
        if isReachable {
            isReconnecting = false
            windowEnd?.cancel()
            windowEnd = nil
        } else if wasReachable {
            isReconnecting = true
            drops += 1
            let drop = drops
            windowEnd = Task { [weak self, clock] in
                do {
                    try await clock.sleep(for: Self.reconnectWindow)
                } catch {
                    return // reached again first
                }
                await self?.windowEnded(drop)
            }
        }
        show()
    }

    private func windowEnded(_ drop: Int) {
        guard drop == drops, !isReachable else {
            return
        }
        isReconnecting = false
        windowEnd = nil
        show()
    }

    private func show() {
        let state = derived
        if state != shown {
            shown = state
            connectionSink.yield(state)
        }
    }

    /// What the screen shows now.
    private var derived: LiveConnectionState {
        if mirroringStatus == .open {
            return .connected(.mirroring)
        }
        if isWatchConnectivityUp {
            return mirroringStatus == .degraded ? .degraded(.mirroring) : .connected(.watchConnectivity)
        }
        return isReconnecting ? .reconnecting : .solo
    }

    private static func result(_ send: @Sendable () async throws -> Void) async -> Result<Void, any Error> {
        do {
            try await send()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
