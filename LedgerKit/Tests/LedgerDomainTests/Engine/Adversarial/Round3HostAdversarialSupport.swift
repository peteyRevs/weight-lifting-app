import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

// Round 3 (G2, after fix round 2): a host written from ADR-004 "The host loop" as amended, including the
// orchestrator's correction on remote haptics (2026-09-29). It is not `SimHost`, `StoringHost` or
// `Replica`: those take the reduce path only when the state is not nil, which the ADR does not say, and
// `SimHost` runs `effects(from:to:)` for every received envelope, the rule the correction replaced.

/// One device's host, ADR-004 read literally:
/// - its own envelope: stamp (hybrid logical clock), `seq` = `highestSeq` + 1, `reduce`, and run
///   `reduce`'s effects (`.persist` appends it, `.transmit` queues it);
/// - a received batch: append it first; if everything `append` newly stored sorts after the newest
///   envelope already applied, reduce it in sort order and run `reduce`'s effects without `.persist` and
///   `.transmit`; otherwise rebuild once with `replay` and run only `effects(from:to:)`;
/// - relaunch: replay the store, run `effects(from: nil, to:)`, and recover the clock from the store.
struct LiteralHost {
    enum Path: Hashable {
        case own, inOrder, rebuild, relaunch
    }

    /// Which envelopes count as "already applied" for the loop's test.
    enum Applied {
        /// Every envelope handed to `reduce` or `replay`, ignored or not.
        case everyReduced
        /// Only envelopes `reduce` accepted (non-empty effects), plus everything a rebuild covered.
        case onlyAccepted
    }

    let device: DeviceID
    let store = InMemoryEventStore()
    /// The device clock minus real time, in seconds.
    var offset: Double
    var hybrid = true
    var applied = Applied.everyReduced
    private(set) var newestStamp: Date?
    private(set) var state: WorkoutState?
    private(set) var newestApplied: EventEnvelope?
    private(set) var outbox: [EventEnvelope] = []
    private(set) var notification: Date?
    private(set) var materialized: WorkoutState?
    private(set) var droppedLog = false
    private(set) var haptics: [Path: Int] = [:]
    /// The most haptics one received batch played.
    private(set) var largestBurst = 0
    /// Times `state` differed from `replay` of the store after an apply.
    private(set) var mismatches = 0

    init(_ device: DeviceID, offset: Double) {
        self.device = device
        self.offset = offset
    }

    func now(_ real: Double) -> Date {
        engineTime(real + offset)
    }

    var log: [EventEnvelope] {
        get async {
            await store.envelopes(for: EngineAdv.workoutID)
        }
    }

    /// The lifter acts on this device at `real` seconds. Returns the envelope, or `nil` when the engine
    /// ignored it (nothing is stored or sent).
    @discardableResult
    mutating func create(_ event: WorkoutEvent, real: Double) async throws -> EventEnvelope? {
        let clock = now(real)
        let stamp = hybrid ? newestStamp.map { max(clock, $0.addingTimeInterval(0.001)) } ?? clock : clock
        newestStamp = max(newestStamp ?? stamp, stamp)
        let seq = await (store.highestSeq(for: EngineAdv.workoutID, device: device) ?? 0) + 1
        let envelope = EventEnvelope(
            event: event, workoutID: EngineAdv.workoutID, device: device, seq: seq, wallClock: stamp
        )
        let (next, effects) = WorkoutEngine.reduce(state, envelope)
        guard !effects.isEmpty else {
            return nil
        }
        state = next
        _ = try await run(effects, path: .own)
        newestApplied = max(newestApplied ?? envelope, envelope)
        await check()
        return envelope
    }

    /// A batch from a peer, as the transport hands it over (maybe shuffled, maybe with copies).
    mutating func receive(_ batch: [EventEnvelope]) async throws {
        for envelope in batch where hybrid {
            newestStamp = max(newestStamp ?? envelope.wallClock, envelope.wallClock)
        }
        let fresh = try await store.append(batch)
        guard let newestFresh = fresh.max() else {
            return
        }
        let before = state
        var accepted: EventEnvelope?
        if fresh.allSatisfy({ envelope in newestApplied.map { $0 < envelope } ?? true }) {
            var played = 0
            for envelope in fresh.sorted() {
                let (next, effects) = WorkoutEngine.reduce(state, envelope)
                state = next
                accepted = effects.isEmpty ? accepted : envelope
                played += try await run(effects.filter(Self.isLocal), path: .inOrder)
            }
            largestBurst = max(largestBurst, played)
        } else {
            let stored = await log
            state = WorkoutEngine.replay(stored)
            accepted = stored.max()
            _ = try await run(WorkoutEngine.effects(from: before, to: state), path: .rebuild)
        }
        let advance = applied == .everyReduced ? newestFresh : accepted
        if let advance {
            newestApplied = max(newestApplied ?? advance, advance)
        }
        await check()
    }

    /// Killed and relaunched (ADR-004 rule 6 and the amendment's recovery on launch).
    mutating func relaunch() async throws {
        let stored = await log
        state = WorkoutEngine.replay(stored)
        newestApplied = stored.max()
        _ = try await run(WorkoutEngine.effects(from: nil, to: state), path: .relaunch)
        newestStamp = nil
        for workout in await store.uncompactedWorkoutIDs() where hybrid {
            for envelope in await store.envelopes(for: workout) {
                newestStamp = max(newestStamp ?? envelope.wallClock, envelope.wallClock)
            }
        }
    }

    static func isLocal(_ effect: Effect) -> Bool {
        switch effect {
        case .persist, .transmit:
            false
        default:
            true
        }
    }

    /// Runs `effects` and returns how many haptics played.
    private mutating func run(_ effects: [Effect], path: Path) async throws -> Int {
        var played = 0
        for effect in effects {
            switch effect {
            case let .persist(envelope):
                #expect(try await store.append([envelope]) == [envelope], "\(device) could not persist its own")
            case let .transmit(envelope):
                outbox.append(envelope)
            case .haptic:
                haptics[path, default: 0] += 1
                played += 1
            case let .scheduleRestNotification(endsAt):
                notification = endsAt
            case .cancelRestNotification:
                notification = nil
            case let .materialize(final):
                materialized = final
            case .discardLog:
                // Not deleted here: compaction against late envelopes is F05's and F17's (see test-findings).
                droppedLog = true
            case .updateLiveActivity:
                break
            }
        }
        return played
    }

    private mutating func check() async {
        mismatches += await state == WorkoutEngine.replay(log) ? 0 : 1
    }
}
