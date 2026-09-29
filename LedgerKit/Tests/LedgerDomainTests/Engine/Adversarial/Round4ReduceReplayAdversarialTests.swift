import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 4 (G2 close-out after the re-plan): the own-action path. ADR-004 says a host reduces its own
/// envelope on `replay` of its stored log, and that the hybrid logical clock makes this equal `replay` of the
/// log with it. A small driver of its own (not `LiteralHost`, `SimHost` or `Replica`) checks exactly that.
@Suite("WorkoutEngine · reduce equals replay for own HLC envelopes (adversarial, round 4)", .tags(.domain))
struct Round4ReduceReplayAdversarialTests {
    typealias Adv = EngineAdv

    /// One device: a keyed log, a hybrid logical clock (round 2's `HybridClock`), and a clock offset.
    struct Device {
        let id: DeviceID
        var offset: Double
        var clock = HybridClock()
        var log: [EnvelopeKey: EventEnvelope] = [:]
        var sent: [EventEnvelope] = []

        var envelopes: [EventEnvelope] {
            Array(log.values)
        }

        mutating func store(_ batch: [EventEnvelope]) {
            for envelope in batch where log[envelope.key] == nil {
                clock.observe(envelope.wallClock)
                log[envelope.key] = envelope
            }
        }

        /// Killed and relaunched: the clock's newest is recovered from the stored log.
        mutating func relaunch() {
            clock = HybridClock()
            for envelope in log.values {
                clock.observe(envelope.wallClock)
            }
        }
    }

    struct Tally {
        var checked = 0
        var accepted = 0
        var early = 0
        var mismatches = 0
        var stillLifting = false
        var everything: [EventEnvelope] = []
    }

    /// One lifter action: on `devices[index]` when its clock reads `now`, stamped by the HLC or (`hybrid` off)
    /// the raw clock; `finishLate` makes it the "Still lifting?" Finish.
    struct Action {
        let index: Int
        let now: Date
        let hybrid: Bool
        let finishLate: Bool
    }

    /// Runs `action` and puts the check's outcome into `tally`.
    static func act(
        _ action: Action,
        on devices: inout [Device],
        into tally: inout Tally,
        using generator: inout SeededGenerator
    ) {
        let (index, now, hybrid, finishLate) = (action.index, action.now, action.hybrid, action.finishLate)
        guard let view = WorkoutEngine.replay(devices[index].envelopes), view.phase == .live else {
            return
        }
        var event = EngineGen.intent(for: view, at: now, sharedAddIDs: [], using: &generator)
        switch event {
        case _ where finishLate:
            // "Still lifting?" → Finish, opened days later: the workout ends at the last activity.
            event = .finished(endedAt: view.exercises.flatMap(\.sets).compactMap(\.doneAt).max() ?? view.startedAt)
        case .finished, .discarded:
            event = .restSkipped
        default:
            break
        }
        let stored = devices[index].envelopes
        let seq = (stored.filter { $0.device == devices[index].id }.map(\.seq).max() ?? 0) + 1
        let stamp = hybrid ? devices[index].clock.stamp(now: now) : now
        let envelope = EventEnvelope(
            event: event, workoutID: Adv.workoutID, device: devices[index].id, seq: seq, wallClock: stamp
        )
        let (reduced, effects) = WorkoutEngine.reduce(view, envelope)
        tally.checked += 1
        tally.early += stored.allSatisfy { $0 < envelope } ? 0 : 1
        tally.mismatches += reduced == WorkoutEngine.replay(stored + [envelope]) ? 0 : 1
        guard !effects.isEmpty else {
            return
        }
        #expect(effects.starts(with: [.persist(envelope), .transmit(envelope)]))
        tally.accepted += 1
        tally.stillLifting = tally.stillLifting || finishLate
        devices[index].store([envelope])
        devices[index].sent.append(envelope)
    }

    /// One seeded session of 2–3 devices: ±30 s skew, clock steps back, relaunches with clock recovery,
    /// partial and shuffled deliveries of each device's own envelopes, and sometimes a late finish.
    static func session(_ seed: PropertySeed, hybrid: Bool) -> Tally {
        var generator = seed.generator
        let ids = [Adv.phone, Adv.watch, Adv.tablet].prefix(Int.random(in: 2 ... 3, using: &generator))
        var devices = ids.map { Device(
            id: $0,
            offset: Double(Int.random(in: -30000 ... 30000, using: &generator)) / 1000
        ) }
        let start = EventEnvelope(
            event: .started(EngineGen.session(using: &generator)), workoutID: Adv.workoutID, device: Adv.phone,
            seq: 1, wallClock: devices[0].clock.stamp(now: engineTime(devices[0].offset))
        )
        devices[0].store([start])
        devices[0].sent = [start]
        var (real, tally) = (0.0, Tally())
        for step in 0 ..< 40 {
            real += Double(Int.random(in: 1 ... 40, using: &generator))
            let index = Int.random(in: devices.indices, using: &generator)
            if generator.chance(5) {
                devices[index].offset -= Double(Int.random(in: 1 ... 30, using: &generator))
            }
            if generator.chance(4) {
                devices[index].relaunch()
            }
            let late = step == 39 && generator.chance(30)
            real += late ? 30 * 86400 : 0
            let now = engineTime(real + devices[index].offset)
            let action = Action(index: index, now: now, hybrid: hybrid, finishLate: late)
            Self.act(action, on: &devices, into: &tally, using: &generator)
            for sender in devices.indices {
                for peer in devices.indices where peer != sender && generator.chance(50) {
                    devices[peer]
                        .store(devices[sender].sent.filter { _ in generator.chance(70) }.shuffled(using: &generator))
                }
            }
        }
        tally.everything = devices.flatMap(\.sent)
        return tally
    }

    @Test(
        """
        Property: 2–3 devices, ±30 s skew, clock steps back, relaunches with clock recovery, partial and shuffled \
        deliveries, and sometimes a "Still lifting?" finish 30 days later: every own action stamped by the HLC \
        sorts last, and reduce on the replayed state equals replay of the log with it
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func ownHLCEnvelope_reduceEqualsReplay(seed: PropertySeed) {
        let tally = Self.session(seed, hybrid: true)
        #expect(tally.checked > 0 && tally.accepted > 0)
        #expect(tally.early == 0, "\(tally.early) HLC stamps did not sort last")
        #expect(tally.mismatches == 0, "reduce differed from replay \(tally.mismatches) times")
        if tally.stillLifting {
            #expect(WorkoutEngine.replay(tally.everything)?.phase == .finished, "the late Finish did not end it")
        }
    }

    @Test("Control: with raw device clocks the same driver stamps early, and reduce then leaves replay")
    func rawClocks_reduceLeavesReplay() {
        var (early, mismatches, lateFinishes) = (0, 0, 0)
        for seed in PropertySeed.all.prefix(100) {
            let tally = Self.session(seed, hybrid: false)
            early += tally.early
            mismatches += tally.mismatches
            lateFinishes += Self.session(seed, hybrid: true).stillLifting ? 1 : 0
        }
        #expect(early > 0 && mismatches > 0, "early \(early), mismatches \(mismatches)")
        #expect(lateFinishes > 0, "no session exercised the 30-day finish")
    }
}
