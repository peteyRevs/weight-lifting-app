import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// A place to keep the wrapper a closure made.
final class SiegeBox<Value: Sendable>: Sendable {
    private let held = Mutex<Value?>(nil)

    func put(_ value: Value) {
        held.withLock { $0 = value }
    }

    var value: Value? {
        held.withLock { $0 }
    }
}

/// One thing a host could get wrong only while two calls are inside it at once (F10 S2 adversarial round 1,
/// criterion 11). Each is the kind of slip an actor that awaits its store makes when a check and its commit,
/// or a commit and its publication, end up on two sides of a suspension.
enum RacyFault: String, CaseIterable, Sendable, CustomStringConvertible {
    /// A stream carries one update twice.
    case repeatsAnUpdate
    /// A stream carries two updates the wrong way round.
    case swapsTwoUpdates
    /// A stream misses one update.
    case dropsAnUpdate
    /// `apply` answers with the workout as it stood when the call arrived, not after its event.
    case answersWithAStaleState
    /// `apply` returns as if it had applied its event, which never reaches the log.
    case swallowsAnApply
    /// A stream opened while a call is in flight starts with "no workout".
    case opensAStreamOnNothing

    var description: String {
        rawValue
    }

    /// The faults that corrupt one stream.
    static let onAStream: [RacyFault] = [.repeatsAnUpdate, .swapsTwoUpdates, .dropsAnUpdate]
}

/// A client between the callers and a real host that passes everything on, except that its fault strikes
/// once, the first time its moment comes while at least two calls are inside. Called one at a time it is the
/// host; so only calls made at once can show it.
actor RacyHost: WorkoutSessionClient {
    /// Which streams a stream fault may strike, by the order they were opened in (the first is 1).
    enum Streams: Sendable {
        case all
        case only(Int)
        case allBut(Int)

        func holds(_ number: Int) -> Bool {
            switch self {
            case .all: true
            case let .only(wanted): number == wanted
            case let .allBut(unwanted): number != unwanted
            }
        }
    }

    private let host: any WorkoutSessionClient
    private let fault: RacyFault?
    private let streams: Streams
    private var inFlight = 0
    private var opened = 0
    /// How often the fault struck: 0 or 1.
    private(set) var strikes = 0
    /// Where it struck: the call, or the stream by the order the streams were opened in.
    private(set) var struckAt = "nowhere"

    init(_ host: any WorkoutSessionClient, _ fault: RacyFault?, on streams: Streams = .all) {
        self.host = host
        self.fault = fault
        self.streams = streams
    }

    /// Whether `wanted` strikes now: it is this client's fault, it has not struck, and `others` calls beside
    /// the one asking are inside.
    private func strikes(_ wanted: RacyFault, beside others: Int = 2, at place: String) -> Bool {
        guard fault == wanted, strikes == 0, inFlight >= others else {
            return false
        }
        strikes = 1
        struckAt = place
        return true
    }

    /// Whether the engine accepts `event` on `state`: a fault on an event it ignores would show nowhere.
    private static func isAccepted(_ event: WorkoutEvent, on state: WorkoutState) -> Bool {
        let envelope = EventBuilders.envelope(event, seq: 1, at: EventBuilders.start, workoutID: state.id)
        return !WorkoutEngine.reduce(state, envelope).1.isEmpty
    }

    private func inside<Value: Sendable>(_ call: () async throws -> Value) async rethrows -> Value {
        inFlight += 1
        defer { inFlight -= 1 }
        return try await call()
    }

    func current() async throws -> WorkoutState? {
        try await host.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await inside { try await host.start(initial) }
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await inside {
            // An honest host never reads the workout before it has the turn; this one does.
            let arrived = try await host.current()
            if let arrived, Self.isAccepted(event, on: arrived), strikes(.swallowsAnApply, at: "apply") {
                return arrived
            }
            let after = try await host.apply(event)
            // Only for an event the engine accepted on what was read: an ignored one answers with the workout
            // as it stands, and any state the host published is a right answer to it.
            let isStale = arrived.map { $0 != after && Self.isAccepted(event, on: $0) } ?? false
            if let arrived, isStale, strikes(.answersWithAStaleState, at: "apply") {
                return arrived
            }
            return after
        }
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await inside { try await host.finish(endedAt: endedAt) }
    }

    func discard(endedAt: Date) async throws {
        try await inside { try await host.discard(endedAt: endedAt) }
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        let inner = await host.updates()
        opened += 1
        let place = "stream \(opened)"
        guard streams.holds(opened) else {
            return inner
        }
        let (stream, continuation) = AsyncStream.makeStream(of: WorkoutSessionUpdate.self)
        let forwarding = Task {
            var isFirst = true
            var held: WorkoutSessionUpdate?
            var before: WorkoutSessionUpdate?
            for await update in inner {
                let first = isFirst
                isFirst = false
                let passed = await self.passed(update, first: first, after: before, holding: &held, at: place)
                for forwarded in passed {
                    continuation.yield(forwarded)
                }
                before = update
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
        return stream
    }

    /// What a stream is given for `update`, which follows `before` on it: the update; or, when a stream fault
    /// strikes, it twice, nothing, or nothing until the next one has gone first.
    ///
    /// A strike is a wrong a reader can see. The engine accepts events that change nothing ("+30s" on a rest
    /// that ends later), and the host publishes an update for each, equal to the one before it. Such an update
    /// twice, or missing, on a stream opened in flight is the stream of an honest host that registered it one
    /// update sooner or later; and two equal updates the wrong way round are the right stream.
    private func passed(
        _ update: WorkoutSessionUpdate,
        first: Bool,
        after before: WorkoutSessionUpdate?,
        holding held: inout WorkoutSessionUpdate?,
        at place: String
    ) -> [WorkoutSessionUpdate] {
        if let waiting = held {
            held = nil
            if waiting == update {
                // Nothing went wrong, so nothing struck: the fault waits for its next moment.
                strikes = 0
                struckAt = "nowhere"
            }
            return [update, waiting]
        }
        guard !first else {
            let onNothing = update.state != nil && strikes(.opensAStreamOnNothing, beside: 1, at: place)
            return [onNothing ? WorkoutSessionUpdate(state: nil) : update]
        }
        let afterLive = before?.live != nil
        let changesTheWorkout = update.live != before?.live
        if changesTheWorkout, strikes(.repeatsAnUpdate, at: place) {
            return [update, update]
        }
        // Only after a live update, so that a reader waiting to be told of a workout has been.
        if afterLive, changesTheWorkout, strikes(.dropsAnUpdate, at: place) {
            return []
        }
        if afterLive, strikes(.swapsTwoUpdates, at: place) {
            held = update
            return []
        }
        return [update]
    }
}
