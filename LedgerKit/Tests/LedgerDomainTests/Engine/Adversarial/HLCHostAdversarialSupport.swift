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
/// - fix round 2 (decision F): it runs `reduce`'s effects for what it created, and only
///   `WorkoutEngine.effects(from:to:)` for what it received or rebuilt, tracking the rest notification
///   and the materialised workout they leave behind;
/// - fix round 2 (decision E): on relaunch its clock's newest is the largest stored `wallClock` across
///   the store's uncompacted logs;
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
    /// The rest-over notification its effects left scheduled (it survives a relaunch, as the OS keeps it).
    private(set) var notification: Date?
    /// The workout its `.materialize` effects left stored (it survives a relaunch, as F05's store does).
    private(set) var materialized: WorkoutState?
    /// Whether a `.discardLog` ran.
    private(set) var droppedLog = false
    /// Haptics run for envelopes it received (must stay 0: remote changes never buzz).
    private(set) var remoteHaptics = 0

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
        try await apply(store.append([envelope]), own: true)
        return envelope
    }

    /// Receives a batch from a peer.
    mutating func receive(_ batch: [EventEnvelope]) async throws {
        for envelope in batch {
            clock.observe(envelope.wallClock)
        }
        try await apply(store.append(batch), own: false)
    }

    /// Killed and relaunched: ADR-004 rule 6 replays the stored log, and the rebuild's effects run from
    /// no state. With `recoverClock`, the ADR-004 amendment (fix round 2, decision E): before it stamps
    /// anything, the clock's newest is the largest stored `wallClock` across the uncompacted logs.
    mutating func relaunch() async {
        let stored = await log
        state = WorkoutEngine.replay(stored)
        naive = state
        newestApplied = stored.max()
        run(WorkoutEngine.effects(from: nil, to: state), own: false)
        clock = HybridClock()
        guard policy.recoverClock else {
            return
        }
        for workout in await store.uncompactedWorkoutIDs() {
            for envelope in await store.envelopes(for: workout) {
                clock.observe(envelope.wallClock)
            }
        }
    }

    /// Runs what it can observe of `effects`: the notification, materialisation and haptics.
    private mutating func run(_ effects: [Effect], own: Bool) {
        for effect in effects {
            switch effect {
            case let .scheduleRestNotification(endsAt):
                notification = endsAt
            case .cancelRestNotification:
                notification = nil
            case let .materialize(final):
                materialized = final
            case .discardLog:
                droppedLog = true
            case .haptic:
                remoteHaptics += own ? 0 : 1
            default:
                break
            }
        }
    }

    /// Applies what `append` newly stored. The whole batch is already in the store, so a rebuild covers
    /// all of it: reducing an envelope after a rebuild that included it would apply it twice (a real
    /// trap for F17, found while building this model).
    private mutating func apply(_ fresh: [EventEnvelope], own: Bool) async throws {
        for envelope in fresh {
            naive = WorkoutEngine.reduce(naive, envelope).0
        }
        guard let newestFresh = fresh.max() else {
            return
        }
        let before = state
        var reduced: [Effect]?
        if state != nil, let newest = newestApplied, fresh.allSatisfy({ newest < $0 }) {
            reduced = []
            for envelope in fresh.sorted() {
                let (next, effects) = WorkoutEngine.reduce(state, envelope)
                state = next
                reduced? += effects
            }
        } else {
            state = await WorkoutEngine.replay(log)
        }
        // Decision F: its own envelope runs `reduce`'s effects; anything received or rebuilt runs only
        // the rebuild effects.
        if own, let reduced {
            run(reduced, own: true)
        } else {
            run(WorkoutEngine.effects(from: before, to: state), own: false)
        }
        newestApplied = max(newestApplied ?? newestFresh, newestFresh)
        let replayed = await WorkoutEngine.replay(log)
        replayMismatches += state == replayed ? 0 : 1
        naiveMismatches += naive == replayed ? 0 : 1
    }
}
