import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

// Round 3 (G2, after fix round 2): a host written from ADR-004 "The host loop". It is not `SimHost`,
// `StoringHost` or `Replica`. Final fix round (re-plan 2026-09-29): the loop has one path for what a host
// receives, so this model now follows it; the round-3 switch between two readings of "already applied"
// (finding 17) went with the in-order path.

/// One device's host, ADR-004 read literally:
/// - its own envelope: stamp (hybrid logical clock), `seq` = `highestSeq` + 1, `reduce`, and run
///   `reduce`'s effects (`.persist` appends it, `.transmit` queues it);
/// - a received batch: append it first; if `append` stored anything new, rebuild once with `replay` and
///   run `effects(from:to:)`;
/// - relaunch: replay the store and recover the clock from it; the launch step plays nothing.
struct LiteralHost {
    enum Path: Hashable {
        case own, rebuild
    }

    let device: DeviceID
    let store = InMemoryWorkoutEventStore()
    /// The device clock minus real time, in seconds.
    var offset: Double
    var hybrid = true
    private(set) var newestStamp: Date?
    private(set) var state: WorkoutState?
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
        await check()
        return envelope
    }

    /// A batch from a peer, as the transport hands it over (maybe shuffled, maybe with copies).
    mutating func receive(_ batch: [EventEnvelope]) async throws {
        for envelope in batch where hybrid {
            newestStamp = max(newestStamp ?? envelope.wallClock, envelope.wallClock)
        }
        guard try await !store.append(batch).isEmpty else {
            return
        }
        let before = state
        state = await WorkoutEngine.replay(log)
        let played = try await run(WorkoutEngine.effects(from: before, to: state), path: .rebuild)
        largestBurst = max(largestBurst, played)
        await check()
    }

    /// Killed and relaunched (ADR-004 rule 6 and the amendment's recovery on launch).
    mutating func relaunch() async throws {
        state = await WorkoutEngine.replay(log)
        newestStamp = nil
        for workout in await store.uncompactedWorkoutIDs() where hybrid {
            for envelope in await store.envelopes(for: workout) {
                newestStamp = max(newestStamp ?? envelope.wallClock, envelope.wallClock)
            }
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
