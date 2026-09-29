import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rule 10, criterion 12 and spec §7.6: what finishing and discarding leave behind, and what happens
/// to an envelope that arrives after the terminal but sorts before it.
@Suite("WorkoutEngine · terminal outcome (adversarial)", .tags(.domain))
struct TerminalOutcomeAdversarialTests {
    typealias Adv = EngineAdv

    static func materialized(_ effects: [Effect]) -> [WorkoutSummary] {
        effects.compactMap { effect in
            if case let .materialize(summary) = effect {
                return summary
            }
            return nil
        }
    }

    @Test("Rule 10 / spec §7.6: finished sets phase and endedAt, clears rest, and materializes a frozen summary.")
    func finished_outcome() throws {
        let live = try #require(Adv.state(after: [
            Adv.start(),
            Adv.env(Adv.logged(0, 0, pounds: "187.5", reps: 5, doneAt: 60), seq: 2, at: 60),
            Adv.env(Adv.logged(0, 1, pounds: "185", reps: 4, doneAt: 240), Adv.watch, seq: 1, at: 240)
        ]))
        #expect(live.rest != nil)
        let (state, effects) = WorkoutEngine.reduce(
            live,
            Adv.env(.finished(endedAt: engineTime(3600)), seq: 3, at: 3601)
        )
        let ended = try #require(state)
        #expect(ended.phase == .finished)
        #expect(ended.endedAt == engineTime(3600))
        #expect(ended.rest == nil, "spec §7.6 rule 31: finishing zeroes the rest")
        let summaries = Self.materialized(effects)
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.workoutID == Adv.workoutID)
        #expect(summary.elapsed == .seconds(3600))
        #expect(summary.doneSets == 2)
        #expect(summary.totalSets == 18)
        // Exact: 187.5 × 5 + 185 × 4 = 1677.5 lb·reps (ADR-007).
        #expect(summary.volume == Volume(gramReps: dec("1677.5") * gramsPerPound))
        #expect(summary.prs.isEmpty)
        #expect(effects.contains(.haptic(.workoutFinished)))
        #expect(effects.contains(.cancelRestNotification))
        #expect(!effects.contains(.discardLog))
    }

    @Test("Rule 10: discarded sets the phase, drops the log and cancels the rest notification; no receipt.")
    func discarded_outcome() {
        let live = Adv.state(after: [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 60), seq: 2, at: 60)])
        let (state, effects) = WorkoutEngine.reduce(live, Adv.env(.discarded(endedAt: engineTime(90)), seq: 3, at: 90))
        #expect(state?.phase == .discarded)
        #expect(effects.contains(.discardLog))
        #expect(effects.contains(.cancelRestNotification))
        #expect(Self.materialized(effects).isEmpty)
        #expect(!effects.contains(.haptic(.workoutFinished)))
    }

    @Test("Rule 24: a finished whose endedAt precedes startedAt (skewed peer) freezes elapsed at zero, not negative.")
    func finished_beforeStart_elapsedIsZero() throws {
        let (_, effects) = WorkoutEngine.reduce(
            Adv.state(after: [Adv.start()]),
            Adv.env(.finished(endedAt: engineTime(-30)), Adv.watch, seq: 1, at: 1)
        )
        let summary = try #require(Self.materialized(effects).first)
        #expect(summary.elapsed == .zero)
    }

    @Test("Criterion 12 / decision #13: a swap with alsoUpdateProgram survives finishing in the state F05 reads.")
    func swapAlsoUpdateProgram_survivesFinish() throws {
        let snapshot = EventBuilders.seedSession()
        let slot = try #require(snapshot.exercises[2].slotID)
        let newID = ExerciseID(EventBuilders.uuid(0xA7))
        let oneOff = ExerciseID(EventBuilders.uuid(0xA8))
        let state = try #require(WorkoutEngine.replay([
            Adv.start(snapshot),
            Adv.env(
                .exerciseSwapped(
                    exerciseIndex: 2,
                    exerciseID: newID,
                    name: "Seated Cable Row",
                    alsoUpdateProgram: true
                ),
                Adv.watch,
                seq: 1,
                at: 10
            ),
            Adv.env(
                .exerciseSwapped(exerciseIndex: 3, exerciseID: oneOff, name: "Neutral-Grip", alsoUpdateProgram: false),
                seq: 2,
                at: 11
            ),
            Adv.env(.finished(endedAt: engineTime(20)), seq: 3, at: 20)
        ]))
        #expect(state.phase == .finished)
        #expect(state.programUpdates == [slot: newID])
        #expect(state.exercises[2].exerciseID == newID)
        #expect(state.exercises[2].originalExerciseID == snapshot.exercises[2].exerciseID)
    }
}

// MARK: - Late envelopes around the terminal (convergence across a partition, criterion 9)

extension TerminalOutcomeAdversarialTests {
    @Test("Criterion 9: a set logged during a partition before the peer's finish is in the converged state.")
    func setLoggedBeforePeersFinish_convergesOnReplay() throws {
        let watchLog = Adv.env(Adv.logged(1, 0, pounds: "55", reps: 10, doneAt: 90), Adv.watch, seq: 1, at: 90)
        let finish = Adv.env(.finished(endedAt: engineTime(100)), seq: 2, at: 100)
        let merged = try #require(WorkoutEngine.replay([Adv.start(), finish, watchLog]))
        #expect(merged.phase == .finished)
        #expect(Adv.row(merged, 1, 0)?.isDone == true)
        #expect(Replica([Adv.start(), finish, watchLog]).state == merged)
        #expect(Replica([Adv.start(), watchLog, finish]).state == merged)
    }

    @Test("Rule 2 is about envelope order: an envelope arriving after the finish but sorting before it is persisted.")
    func lateEnvelopeSortingBeforeFinish_isPersisted() {
        let finish = Adv.env(.finished(endedAt: engineTime(100)), seq: 2, at: 100)
        let watchLog = Adv.env(Adv.logged(1, 0, pounds: "55", reps: 10, doneAt: 90), Adv.watch, seq: 1, at: 90)
        let finished = Adv.state(after: [Adv.start(), finish])
        let (_, effects) = WorkoutEngine.reduce(finished, watchLog)
        // Replay applies this envelope (it sorts before the finish), so the device must keep it; `.persist`
        // is the engine's only way to say so (Effect.persist: "Append the envelope to the local log").
        #expect(effects.contains(.persist(watchLog)), "reduce returned \(effects); the late set is never stored")
    }

    @Test("Rule 1 says early envelopes are buffered: reduce on nil still asks the device to persist one.")
    func envelopeBeforeStarted_isPersisted() {
        let early = Adv.env(Adv.logged(0, 0, doneAt: 5), Adv.watch, seq: 1, at: 5)
        let (state, effects) = WorkoutEngine.reduce(nil, early)
        #expect(state == nil)
        #expect(effects.contains(.persist(early)), "reduce returned \(effects); the buffered envelope is never stored")
    }

    @Test("A peer's earlier started that loses on this device is still persisted, or the two logs never agree.")
    func losingStarted_isPersisted() {
        let phoneStart = Adv.start(EventBuilders.seedSession(), Adv.phone, seq: 1, at: 5)
        let watchStart = Adv.start(EventBuilders.seedSession(autoRest: false), Adv.watch, seq: 1, at: 3)
        let (_, effects) = WorkoutEngine.reduce(Adv.state(after: [phoneStart]), watchStart)
        // Replay of both picks the watch's (it sorts first), so the phone must keep it.
        #expect(WorkoutEngine.replay([phoneStart, watchStart])?.autoRest == false)
        #expect(effects.contains(.persist(watchStart)), "reduce returned \(effects)")
    }
}
