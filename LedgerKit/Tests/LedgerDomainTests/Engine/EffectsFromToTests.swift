import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Fix round 2, orchestrator decision F: `WorkoutEngine.effects(from:to:)`, the effects a rebuild runs
/// for envelopes the host received; with the re-plan (2026-09-29, decision 3), at most one set haptic.
@Suite("WorkoutEngine · rebuild effects (decision F, re-plan)", .tags(.domain))
struct EffectsFromToTests {
    /// The live seed session, then the state after `events` (one phone envelope every 10 s from 10 s).
    static func after(_ events: [WorkoutEvent]) throws -> WorkoutState {
        try Engine.run(events).state
    }

    @Test("No change, no effects; a started arriving from nothing only redraws")
    func unchanged_andStarted() throws {
        let live = try Engine.live()
        #expect(WorkoutEngine.effects(from: live, to: live).isEmpty)
        #expect(WorkoutEngine.effects(from: nil, to: nil).isEmpty)
        #expect(WorkoutEngine.effects(from: nil, to: live) == [.updateLiveActivity])
    }

    @Test("A remote set log: one haptic, the rest it starts is scheduled, and the live activity redraws")
    func remoteSetLog_buzzesAndSchedules() throws {
        let live = try Engine.live()
        let logged = try Self.after([Engine.logged(0, 0, at: 10)])
        #expect(WorkoutEngine.effects(from: live, to: logged) == [
            .haptic(.setLogged),
            .scheduleRestNotification(endsAt: Engine.at(160)),
            .updateLiveActivity
        ])
        // A change that leaves the rest and every set's doneness alone only redraws.
        let target = WorkoutEvent.setTargetChanged(
            exerciseIndex: 0,
            setID: Engine.set(0, 1),
            weight: .pounds(190),
            reps: nil
        )
        let targeted = try Self.after([Engine.logged(0, 0, at: 10), target])
        #expect(WorkoutEngine.effects(from: logged, to: targeted) == [.updateLiveActivity])
    }

    @Test("A remote skip cancels; a remote +30s reschedules")
    func remoteRestChanges() throws {
        let resting = try Self.after([.restStarted(endsAt: Engine.at(100), total: .seconds(90))])
        let skipped = try Self.after([.restStarted(endsAt: Engine.at(100), total: .seconds(90)), .restSkipped])
        let extended = try Self.after([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            Engine.extend(tapped: 20)
        ])
        #expect(WorkoutEngine.effects(from: resting, to: skipped) == [.cancelRestNotification, .updateLiveActivity])
        #expect(WorkoutEngine.effects(from: resting, to: extended) == [
            .scheduleRestNotification(endsAt: Engine.at(130)),
            .updateLiveActivity
        ])
    }

    @Test("The workout ends: finished materialises its final state, discarded drops the log; both cancel the rest")
    func terminals() throws {
        let resting = try Self.after([.restStarted(endsAt: Engine.at(100), total: .seconds(90))])
        let finished = try Self.after([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            .finished(endedAt: Engine.at(20))
        ])
        let discarded = try Self.after([.discarded(endedAt: Engine.at(10))])
        #expect(WorkoutEngine.effects(from: resting, to: finished) == [
            .materialize(finished),
            .cancelRestNotification,
            .updateLiveActivity
        ])
        // With no rest running the cancel still comes, as `reduce`'s does.
        #expect(try WorkoutEngine.effects(from: Engine.live(), to: discarded) == [
            .discardLog,
            .cancelRestNotification,
            .updateLiveActivity
        ])
        // Both finishes arrived before the started (finding 13c): the rebuild from nothing materialises.
        #expect(WorkoutEngine.effects(from: nil, to: finished) == [
            .materialize(finished),
            .cancelRestNotification,
            .updateLiveActivity
        ])
    }

    @Test("A late envelope that changes a finished workout materialises it again; one that changes nothing does not")
    func lateEnvelope_rematerializes() throws {
        let finished = try Self.after([.finished(endedAt: Engine.at(10))])
        var changed = finished
        changed.exercises[0].sets[0].reps = .one
        #expect(WorkoutEngine.effects(from: finished, to: changed) == [.materialize(changed), .updateLiveActivity])
        // A late set log that sorts before the finish re-materialises, and does not buzz: the workout is over.
        var logged = finished
        logged.exercises[0].sets[0].doneAt = Engine.at(5)
        #expect(WorkoutEngine.effects(from: finished, to: logged) == [.materialize(logged), .updateLiveActivity])
        #expect(WorkoutEngine.effects(from: finished, to: finished).isEmpty)
        // A late discard that sorts before the finish: the log is dropped (F05 then deletes the workout).
        var discarded = finished
        discarded.phase = .discarded
        #expect(WorkoutEngine.effects(from: finished, to: discarded) == [
            .discardLog,
            .cancelRestNotification,
            .updateLiveActivity
        ])
    }

    @Test(
        """
        Every step of random sessions: the rebuild effects are reduce's own, less persist and transmit, less \\
        every haptic but a live set log that made a set done, and less a schedule or cancel that leaves the rest
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func matchesReduce_onEveryStep(seed: PropertySeed) {
        var workout = RandomWorkout(seed: seed)
        var state: WorkoutState?
        for envelope in workout.log(steps: 40) {
            let (next, reduced) = WorkoutEngine.reduce(state, envelope)
            let ended = next.map { $0.phase != .live && $0.phase != state?.phase } ?? false
            let newlyDone = next?.phase == .live && (next?.doneSets ?? 0) > (state?.doneSets ?? 0)
            let expected = reduced.filter { effect in
                switch effect {
                case .haptic(.setLogged):
                    newlyDone
                case .persist, .transmit, .haptic:
                    false
                case .scheduleRestNotification, .cancelRestNotification:
                    ended || next?.rest != state?.rest
                default:
                    true
                }
            }
            #expect(WorkoutEngine.effects(from: state, to: next) == expected, "after \(envelope.event)")
            state = next
        }
    }

    @Test(
        """
        Finding 13c: a host that runs the rebuild effects materialises the final state in every arrival order, \\
        including those where both finishes arrive before the started
        """
    )
    func rebuildEffects_materializeInEveryArrivalOrder() async throws {
        let log = [
            EngineAdv.start(),
            EngineAdv.env(EngineAdv.logged(0, 0, doneAt: 60), seq: 2, at: 60),
            EngineAdv.env(EngineAdv.logged(0, 1, doneAt: 90), EngineAdv.watch, seq: 1, at: 90),
            EngineAdv.env(.finished(endedAt: engineTime(98)), EngineAdv.watch, seq: 2, at: 98),
            EngineAdv.env(.finished(endedAt: engineTime(100)), seq: 3, at: 100),
            EngineAdv.env(EngineAdv.logged(0, 2, doneAt: 95), EngineAdv.watch, seq: 3, at: 95)
        ]
        let expected = try #require(WorkoutEngine.replay(log))
        #expect(expected.phase == .finished && expected.doneSets == 3)
        var generator = SeededGenerator(seed: 0x13C)
        for _ in 0 ..< 60 {
            var host = SimHost(EngineAdv.tablet, offset: 0)
            for envelope in log.shuffled(using: &generator) {
                try await host.receive([envelope])
            }
            #expect(host.materialized == expected)
            #expect(host.notification == nil)
            // Re-plan: each rebuild buzzes at most once, only for the three set logs, and only while the
            // workout is live (an order that brings a set after both finishes plays none for it).
            #expect(host.largestRemoteBurst <= 1 && host.remoteHaptics <= 3)
        }
    }
}

// MARK: - The set haptic (re-plan 2026-09-29, decision 3)

extension EffectsFromToTests {
    @Test(
        """
        Decision 3 (re-plan): one haptic per rebuild that shows a newly done set while the workout is live: one \
        for a single remote set, one for a reconnect batch of ten, none for an un-log, and none when no set \
        became done
        """
    )
    func setHaptic_oncePerRebuild() throws {
        let buzzes = { (old: WorkoutState?, new: WorkoutState?) in
            WorkoutEngine.effects(from: old, to: new).count(where: { $0 == .haptic(.setLogged) })
        }
        let live = try Engine.live()
        let one = try Self.after([Engine.logged(0, 0, at: 10)])
        #expect(buzzes(live, one) == 1)
        // A reconnect batch: ten sets across three exercises, applied by one rebuild.
        let rows = [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1)]
        let ten = try Self.after(rows.enumerated().map { Engine.logged($1.0, $1.1, at: Double(10 * ($0 + 1))) })
        #expect(ten.doneSets == 10)
        #expect(buzzes(live, ten) == 1)
        #expect(buzzes(nil, ten) == 1, "a rebuild from nothing (the started arrived last) buzzes once too")
        // An un-log: a set done before is not done now.
        let unlogged = try Self.after([
            Engine.logged(0, 0, at: 10),
            .setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0))
        ])
        #expect(buzzes(one, unlogged) == 0)
        // No newly done set: a re-log of a done set, a rest change, a finish.
        let relogged = try Self.after([Engine.logged(0, 0, at: 10), Engine.logged(0, 0, pounds: 190, at: 20)])
        #expect(buzzes(one, relogged) == 0)
        let skipped = try Self.after([Engine.logged(0, 0, at: 10), .restSkipped])
        #expect(buzzes(one, skipped) == 0)
        let finished = try Self.after([Engine.logged(0, 0, at: 10), .finished(endedAt: Engine.at(20))])
        #expect(buzzes(one, finished) == 0, "a remote finish plays no haptic here")
    }

    @Test(
        """
        Orchestrator (2026-09-29): a rebuild that ends finished or discarded never buzzes, even when a late set \
        became done: a set arriving before a peer's finish, a discarded log arriving whole or after its sets
        """
    )
    func setHaptic_neverWhenTheWorkoutEnded() throws {
        let buzzes = { (old: WorkoutState?, new: WorkoutState?) in
            WorkoutEngine.effects(from: old, to: new).count(where: { $0 == .haptic(.setLogged) })
        }
        let live = try Engine.live()
        // The peer finished at 20 s; the watch's set, logged at 15 s, arrives after the finish.
        let finished = try Self.after([.restSkipped, .finished(endedAt: Engine.at(20))])
        let lateSet = try Self.after([Engine.logged(0, 0, at: 15), .finished(endedAt: Engine.at(20))])
        #expect(lateSet.phase == .finished && lateSet.doneSets == 1)
        #expect(buzzes(finished, lateSet) == 0)
        #expect(WorkoutEngine.effects(from: finished, to: lateSet).contains(.materialize(lateSet)))
        // A discarded log with a done set: arriving whole (from nothing), or its sets and discard in one batch.
        let discarded = try Self.after([Engine.logged(0, 0, at: 10), .discarded(endedAt: Engine.at(20))])
        #expect(discarded.doneSets == 1)
        #expect(buzzes(nil, discarded) == 0)
        #expect(buzzes(live, discarded) == 0)
        // The live cases are unchanged: exactly one.
        #expect(try buzzes(live, Self.after([Engine.logged(0, 0, at: 10)])) == 1)
        let batch = try Self.after([
            Engine.logged(0, 0, at: 10),
            Engine.logged(0, 1, at: 20),
            Engine.logged(1, 0, at: 30)
        ])
        #expect(buzzes(live, batch) == 1 && buzzes(nil, batch) == 1)
    }
}
