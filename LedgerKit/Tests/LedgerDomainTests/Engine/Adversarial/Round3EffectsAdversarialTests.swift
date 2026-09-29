import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): `WorkoutEngine.effects(from:to:)` (decision F) against `reduce`'s own
/// effects for the same transition, and the order of what a discard asks for.
@Suite("WorkoutEngine · rebuild effects (adversarial, round 3)", .tags(.domain))
struct Round3EffectsAdversarialTests {
    typealias Adv = EngineAdv

    /// `reduce`'s effects as a rebuild should run them: no persist or transmit, no haptic but the set
    /// haptic when a set became done in a live workout (final fix round, decision 3), and no schedule or
    /// cancel that leaves the rest as it was (a replace with the same end).
    static func rebuildShare(of effects: [Effect], from old: WorkoutState?, to new: WorkoutState?) -> [Effect] {
        let ended = new.map { $0.phase != .live && $0.phase != old?.phase } ?? false
        let newlyDone = new?.phase == .live && (new?.doneSets ?? 0) > (old?.doneSets ?? 0)
        return effects.filter { effect in
            switch effect {
            case .haptic(.setLogged):
                newlyDone
            case .persist, .transmit, .haptic:
                false
            case .scheduleRestNotification, .cancelRestNotification:
                ended || new?.rest != old?.rest
            default:
                true
            }
        }
    }

    @Test(
        """
        Property: along seeded two-device intent logs (stale rows, shown and unshown +30s, terminals, envelopes \
        after the end), effects(from:to:) equals reduce's effects for the same step, less persist, transmit \
        and every haptic but the set log that made a set done; it buzzes at most once
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func matchesReduce_onIntentLogs(seed: PropertySeed) throws {
        var generator = seed.generator
        let session = EngineGen.session(using: &generator)
        var state = WorkoutEngine.reduce(nil, Adv.start(session)).0
        var seqs: [DeviceID: UInt64] = [Adv.phone: 1]
        for step in 1 ... 60 {
            let device = generator.chance(50) ? Adv.phone : Adv.watch
            seqs[device, default: 0] += 1
            let now = engineTime(Double(step * 20))
            let view = try #require(state)
            let event = EngineGen.intent(for: view, at: now, sharedAddIDs: [], using: &generator)
            let envelope = EventBuilders.envelope(event, device: device, seq: seqs[device, default: 0], at: now)
            let (next, effects) = WorkoutEngine.reduce(state, envelope)
            let rebuild = WorkoutEngine.effects(from: state, to: next)
            #expect(rebuild == Self.rebuildShare(of: effects, from: state, to: next), "after \(event)")
            #expect(rebuild.count(where: { $0 == .haptic(.setLogged) }) <= 1 && !rebuild
                .contains(.haptic(.workoutFinished)))
            state = next
        }
    }

    @Test(
        """
        Finding 21: a started whose snapshot carries a rest (well-formed: it ends within an hour of the start) \
        schedules its notification when a rebuild applies it, but not when reduce applies it
        """
    )
    func startedWithRest_reduceSchedulesItToo() {
        var snapshot = EventBuilders.seedSession()
        snapshot.rest = RestTimer(endsAt: engineTime(90), total: .seconds(90))
        let started = Adv.start(snapshot)
        #expect(started.isWellFormed)
        let (state, effects) = WorkoutEngine.reduce(nil, started)
        #expect(WorkoutEngine.effects(from: nil, to: state).contains(.scheduleRestNotification(endsAt: engineTime(90))))
        #expect(effects.contains(.scheduleRestNotification(endsAt: engineTime(90))), "reduce: \(effects)")
    }

    @Test(
        """
        Held: a discard's effects put persist and transmit before discardLog (the device stores and sends the \
        discard before it drops the log), and a rebuild's discardLog before the cancel and the redraw
        """
    )
    func discardLog_order() {
        let resting = Adv.state(after: [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)])
        let discard = Adv.env(.discarded(endedAt: engineTime(20)), seq: 3, at: 20)
        let (discarded, own) = WorkoutEngine.reduce(resting, discard)
        #expect(own == [
            .persist(discard),
            .transmit(discard),
            .discardLog,
            .cancelRestNotification,
            .updateLiveActivity
        ])
        let rebuilt = WorkoutEngine.effects(from: resting, to: discarded)
        #expect(rebuilt == [.discardLog, .cancelRestNotification, .updateLiveActivity])
        // From nothing (a relaunch, or a log whose started arrived last): no materialise, just the drop.
        #expect(WorkoutEngine.effects(from: nil, to: discarded) == rebuilt)
    }
}
