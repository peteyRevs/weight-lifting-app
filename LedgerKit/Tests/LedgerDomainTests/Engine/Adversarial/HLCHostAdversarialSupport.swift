import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

// Round 2 models of the host (F10/F17) as the fix round's contract describes it, written from ADR-004's
// amendment and the doc comments on `reduce`, `replay`, `Effect` and `WorkoutEventStore`, not from the
// implementer's `HLCDevice` or `StoringHost`.

/// ADR-004's hybrid logical clock (amendment 2026-09-29):
/// `wallClock = max(now, newest wallClock seen or sent + 1 ms)`.
struct HybridClock {
    private(set) var newest: Date?

    /// Notes a stamp this device received.
    mutating func observe(_ stamp: Date) {
        newest = max(newest ?? stamp, stamp)
    }

    /// The stamp for an envelope this device creates when its own clock reads `now`; it counts as sent.
    mutating func stamp(now: Date) -> Date {
        let stamp = newest.map { max(now, $0.addingTimeInterval(0.001)) } ?? now
        newest = stamp
        return stamp
    }
}

/// How a simulated host stamps envelopes and recovers after a relaunch.
struct HostPolicy: Sendable {
    /// Stamp with the hybrid logical clock; `false` stamps the raw device clock (the pre-amendment model).
    var hybridClock = true
    /// On relaunch, rebuild the clock's `newest` from the stored log; `false` starts it empty.
    var recoverClock = true
}

/// One device's host:
/// - it stamps what it creates (`policy`), takes `seq` from `highestSeq` + 1, stores it (`.persist`
///   before `.transmit`), and reduces it;
/// - it appends every received batch first and applies only what `append` newly stored: `reduce`, in
///   sort order, when all of it sorts after the newest envelope applied (ADR-004 rule 2), else one
///   rebuild with `replay` of the store;
/// - `naive` shadows it with a host that reduces every newly stored envelope in arrival order.
struct SimHost {
    let device: DeviceID
    let policy: HostPolicy
    let store = InMemoryEventStore()
    /// The device clock minus real time, in seconds (skew; a step back lowers it).
    var offset: Double
    private(set) var clock = HybridClock()
    private(set) var state: WorkoutState?
    private(set) var naive: WorkoutState?
    private(set) var newestApplied: EventEnvelope?
    /// Times `state` differed from `replay` of the store after an apply (must stay 0).
    private(set) var replayMismatches = 0
    /// Times `naive` differed from `replay` of the store after an apply.
    private(set) var naiveMismatches = 0
    /// Envelopes this host created that did not sort after everything it had stored.
    private(set) var causalViolations: [EnvelopeKey] = []

    init(_ device: DeviceID, offset: Double, policy: HostPolicy = HostPolicy()) {
        self.device = device
        self.offset = offset
        self.policy = policy
    }

    /// This device's clock at real time `real` (seconds after the fixture start).
    func now(_ real: Double) -> Date {
        engineTime(real + offset)
    }

    var log: [EventEnvelope] {
        get async {
            await store.envelopes(for: EngineAdv.workoutID)
        }
    }

    /// Records `event` at real time `real`.
    mutating func create(_ event: WorkoutEvent, real: Double) async throws -> EventEnvelope {
        let seen = await log
        let seq = await (store.highestSeq(for: EngineAdv.workoutID, device: device) ?? 0) + 1
        let wallClock = policy.hybridClock ? clock.stamp(now: now(real)) : now(real)
        let envelope = EventEnvelope(
            event: event, workoutID: EngineAdv.workoutID, device: device, seq: seq, wallClock: wallClock
        )
        if let newest = seen.max(), !(newest < envelope) {
            causalViolations.append(envelope.key)
        }
        try await apply(store.append([envelope]))
        return envelope
    }

    /// Receives a batch from a peer.
    mutating func receive(_ batch: [EventEnvelope]) async throws {
        for envelope in batch {
            clock.observe(envelope.wallClock)
        }
        try await apply(store.append(batch))
    }

    /// Killed and relaunched: ADR-004 rule 6 replays the stored log.
    mutating func relaunch() async {
        let stored = await log
        state = WorkoutEngine.replay(stored)
        naive = state
        newestApplied = stored.max()
        clock = HybridClock()
        if policy.recoverClock, let newest = newestApplied {
            clock.observe(newest.wallClock)
        }
    }

    /// Applies what `append` newly stored. The whole batch is already in the store, so a rebuild covers
    /// all of it: reducing an envelope after a rebuild that included it would apply it twice (a real
    /// trap for F17, found while building this model).
    private mutating func apply(_ fresh: [EventEnvelope]) async throws {
        for envelope in fresh {
            naive = WorkoutEngine.reduce(naive, envelope).0
        }
        guard let newestFresh = fresh.max() else {
            return
        }
        if state != nil, let newest = newestApplied, fresh.allSatisfy({ newest < $0 }) {
            for envelope in fresh.sorted() {
                state = WorkoutEngine.reduce(state, envelope).0
            }
        } else {
            state = await WorkoutEngine.replay(log)
        }
        newestApplied = max(newestApplied ?? newestFresh, newestFresh)
        let replayed = await WorkoutEngine.replay(log)
        replayMismatches += state == replayed ? 0 : 1
        naiveMismatches += naive == replayed ? 0 : 1
    }
}
