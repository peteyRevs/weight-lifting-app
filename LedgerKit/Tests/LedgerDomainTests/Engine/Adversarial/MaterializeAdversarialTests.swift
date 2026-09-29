import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: `.materialize(finalState)` (finding 8's decision), the receipt F05 builds from it with
/// `WorkoutEngine.summary`, and the re-materialisation rule for late envelopes (finding 4's decision).
@Suite("WorkoutEngine · materialisation (adversarial, round 2)", .tags(.domain))
struct MaterializeAdversarialTests {
    typealias Adv = EngineAdv

    static func materialized(_ effects: [Effect]) -> [WorkoutState] {
        effects.compactMap { effect in
            guard case let .materialize(state) = effect else {
                return nil
            }
            return state
        }
    }

    /// A three-hour workout from both devices: two bench sets, a watch weight bump, a program swap of
    /// exercise 1 and one set of it, then the finish.
    static let threeHours: [EventEnvelope] = [
        Adv.start(),
        Adv.env(Adv.logged(0, 0, pounds: "187.5", reps: 5, doneAt: 600), seq: 2, at: 600),
        Adv.env(
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 2), weight: pounds("190"), reps: nil),
            Adv.watch,
            seq: 1,
            at: 700
        ),
        Adv.env(Adv.logged(0, 1, pounds: "185", reps: 4, doneAt: 900), Adv.watch, seq: 2, at: 900),
        Adv.env(
            .exerciseSwapped(
                exerciseIndex: 1,
                exerciseID: ExerciseID(EventBuilders.uuid(0xD1B)),
                name: "Dips",
                alsoUpdateProgram: true
            ),
            seq: 3,
            at: 1200
        ),
        Adv.env(Adv.logged(1, 0, pounds: "55", reps: 10, doneAt: 1500), seq: 4, at: 1500),
        Adv.env(.finished(endedAt: engineTime(10800)), seq: 5, at: 10800)
    ]

    @Test("A three-hour workout: .materialize carries exactly the final state, and summary builds the receipt from it")
    func materialize_threeHourWorkout_payloadAndReceipt() throws {
        let (state, effects) = Adv.fold(Self.threeHours)
        let final = try #require(state)
        #expect(effects.flatMap(Self.materialized) == [final])
        #expect(WorkoutEngine.replay(Self.threeHours.reversed()) == final)
        #expect(final.phase == .finished && final.rest == nil && final.endedAt == engineTime(10800))
        #expect(final.programUpdates == [SlotID(EventBuilders.uuid(0xE001)): ExerciseID(EventBuilders.uuid(0xD1B))])
        #expect(Adv.row(final, 0, 2)?.weight == pounds("190"))
        let record = PersonalRecord(
            exerciseID: ExerciseID(EventBuilders.uuid(0xE000)), kind: .weightAtReps(pounds("187.5"), Reps(clamping: 5)),
            previous: nil, achievedAt: engineTime(600), workoutID: Adv.workoutID
        )
        let summary = WorkoutEngine.summary(final, prs: [record])
        #expect(summary.workoutID == Adv.workoutID)
        #expect(summary.elapsed == .seconds(10800))
        #expect(summary.doneSets == 3 && summary.totalSets == 18)
        #expect(summary.volume == Volume(gramReps: dec("2227.5") * gramsPerPound))
        #expect(summary.prs == [record])
        #expect(summary.rows.map(\.name) == final.exercises.map(\.name))
        #expect(summary.rows[1].name == "Dips")
    }

    @Test(
        "Random single-device sessions: the one .materialize is the reduced state and replay's, and only for a finish",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func materialize_matchesReplay(seed: PropertySeed) {
        var generator = seed.generator
        let session = EngineGen.session(using: &generator)
        var log = [Adv.start(session)]
        var state = WorkoutEngine.reduce(nil, log[0]).0
        var payloads: [WorkoutState] = []
        for step in 1 ... 25 {
            let now = engineTime(Double(step * 20))
            let event = step == 25 ? .finished(endedAt: now) : EngineGen.intent(
                for: state ?? session, at: now, sharedAddIDs: [], using: &generator
            )
            log.append(Adv.env(event, seq: UInt64(step + 1), at: Double(step * 20)))
            let (next, effects) = WorkoutEngine.reduce(state, log[step])
            state = next
            payloads += Self.materialized(effects)
        }
        let replayed = WorkoutEngine.replay(log.shuffled(using: &generator))
        #expect(replayed == state)
        #expect(payloads == (state?.phase == .finished ? [state].compactMap(\.self) : []))
        if let final = payloads.first {
            #expect(WorkoutEngine.summary(final, prs: []).doneSets == final.doneSets)
            #expect(WorkoutEngine.summary(final, prs: []).elapsed == final.elapsed(at: .distantFuture))
        }
    }
}

// MARK: - Late envelopes after the finish

extension MaterializeAdversarialTests {
    /// A host that runs `.materialize`, then applies finding 4's decision: when replaying the finished
    /// log gives a different final state, it materialises again (an idempotent upsert).
    struct Materializer {
        var host = StoringHost()
        private(set) var record: WorkoutState?

        mutating func receive(_ envelope: EventEnvelope) async throws {
            let effects = try await host.receive([envelope])
            record = MaterializeAdversarialTests.materialized(effects).last ?? record
            guard record != nil, let replayed = try await host.replayed(), replayed.phase == .finished else {
                return
            }
            record = replayed
        }
    }

    @Test(
        """
        Late envelopes: in every arrival order the stored record ends as replay of the whole log, or, when \
        the finish never reached reduce on a live state, nothing is stored yet and the log is listed unmaterialized
        """
    )
    func rematerialization_convergesInEveryArrivalOrder() async throws {
        let log = [
            Adv.start(),
            Adv.env(Adv.logged(0, 0, doneAt: 60), seq: 2, at: 60),
            Adv.env(Adv.logged(0, 1, doneAt: 90), Adv.watch, seq: 1, at: 90),
            Adv.env(
                .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 1), weight: pounds("190"), reps: nil),
                Adv.watch,
                seq: 2,
                at: 95
            ),
            Adv.env(.finished(endedAt: engineTime(98)), Adv.watch, seq: 3, at: 98),
            Adv.env(.finished(endedAt: engineTime(100)), seq: 3, at: 100),
            Adv.env(Adv.logged(0, 2, doneAt: 105), Adv.watch, seq: 4, at: 105)
        ]
        let expected = try #require(WorkoutEngine.replay(log))
        #expect(expected.endedAt == engineTime(98) && expected.doneSets == 2)
        var generator = SeededGenerator(seed: 0x4A7)
        var notYet = 0
        for _ in 0 ..< 60 {
            var host = Materializer()
            for envelope in log.shuffled(using: &generator) {
                try await host.receive(envelope)
            }
            if host.record == nil {
                notYet += 1
                #expect(try await host.host.store.unmaterializedWorkoutIDs() == [Adv.workoutID])
            } else {
                #expect(host.record == expected)
            }
        }
        #expect(notYet < 60)
    }
}
