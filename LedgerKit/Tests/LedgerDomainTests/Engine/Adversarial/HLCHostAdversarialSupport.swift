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

/// One device's host, on ADR-004's host loop as re-planned (2026-09-29):
/// - it stamps what it creates (`policy`), takes `seq` from `highestSeq` + 1, reduces it, and runs
///   `reduce`'s effects (`.persist` appends it to its store);
/// - it appends every received batch first and, when `append` stored anything new, rebuilds once with
///   `replay` of the store and runs `WorkoutEngine.effects(from:to:)`, tracking the rest notification,
///   the materialised workout and the haptics they leave behind;
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
    /// Haptics its rebuilds played for what it received.
    private(set) var remoteHaptics = 0
    /// The most haptics one rebuild played (re-plan: at most one, however many sets it brought).
    private(set) var largestRemoteBurst = 0

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

    /// Records `event` at real time `real`: stamp, reduce, and run `reduce`'s effects.
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
        let (next, effects) = WorkoutEngine.reduce(state, envelope)
        #expect(!effects.isEmpty, "\(device) created an envelope its own state ignores: \(event)")
        state = next
        naive = WorkoutEngine.reduce(naive, envelope).0
        try await run(effects)
        await check()
        return envelope
    }

    /// Receives a batch from a peer: append, and rebuild once if anything was new.
    mutating func receive(_ batch: [EventEnvelope]) async throws {
        for envelope in batch {
            clock.observe(envelope.wallClock)
        }
        let fresh = try await store.append(batch)
        guard !fresh.isEmpty else {
            return
        }
        for envelope in fresh {
            naive = WorkoutEngine.reduce(naive, envelope).0
        }
        let before = state
        state = await WorkoutEngine.replay(log)
        let played = try await run(WorkoutEngine.effects(from: before, to: state))
        remoteHaptics += played
        largestRemoteBurst = max(largestRemoteBurst, played)
        await check()
    }

    /// Killed and relaunched: ADR-004 rule 6 replays the stored log. The launch step plays nothing (the
    /// doc on `effects(from:to:)`); the notification and the stored workout survive the relaunch. With
    /// `recoverClock`, the ADR-004 amendment (fix round 2, decision E): before it stamps anything, the
    /// clock's newest is the largest stored `wallClock` across the uncompacted logs.
    mutating func relaunch() async {
        state = await WorkoutEngine.replay(log)
        naive = state
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

    /// Runs what it can observe of `effects` and returns how many haptics played.
    @discardableResult
    private mutating func run(_ effects: [Effect]) async throws -> Int {
        var played = 0
        for effect in effects {
            switch effect {
            case let .persist(envelope):
                _ = try await store.append([envelope])
            case let .scheduleRestNotification(endsAt):
                notification = endsAt
            case .cancelRestNotification:
                notification = nil
            case let .materialize(final):
                materialized = final
            case .discardLog:
                droppedLog = true
            case .haptic:
                played += 1
            case .transmit, .updateLiveActivity:
                break
            }
        }
        return played
    }

    private mutating func check() async {
        let replayed = await WorkoutEngine.replay(log)
        replayMismatches += state == replayed ? 0 : 1
        naiveMismatches += naive == replayed ? 0 : 1
    }
}
