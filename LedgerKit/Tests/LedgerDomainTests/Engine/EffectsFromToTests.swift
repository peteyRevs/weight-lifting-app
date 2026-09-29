import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Fix round 2, orchestrator decision F: `WorkoutEngine.effects(from:to:)`, the effects a rebuild runs
/// for envelopes the host received.
@Suite("WorkoutEngine · rebuild effects (decision F)", .tags(.domain))
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

    @Test("A remote set log: the rest it starts is scheduled, the live activity redraws, and nothing buzzes")
    func remoteSetLog_schedulesWithoutHaptic() throws {
        let live = try Engine.live()
        let logged = try Self.after([Engine.logged(0, 0, at: 10)])
        #expect(WorkoutEngine.effects(from: live, to: logged) == [
            .scheduleRestNotification(endsAt: Engine.at(160)),
            .updateLiveActivity
        ])
        // A change that leaves the rest alone only redraws.
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
        changed.exercises[0].sets[0].doneAt = Engine.at(5)
        #expect(WorkoutEngine.effects(from: finished, to: changed) == [.materialize(changed), .updateLiveActivity])
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
        Every step of random sessions: the rebuild effects are reduce's own, less persist, transmit and \\
        haptics, and less a schedule or cancel that leaves the rest as it was
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
            let expected = reduced.filter { effect in
                switch effect {
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
            #expect(host.remoteHaptics == 0)
        }
    }
}
