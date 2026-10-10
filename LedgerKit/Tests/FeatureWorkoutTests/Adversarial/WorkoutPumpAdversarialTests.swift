import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S5 criteria 7 and 8: the pump against overlap. Taps that arrive while a call waits, a stream that
/// is behind the calls' answers, another hand between two taps, a refusal in the middle, the cover's tasks
/// cancelled and started again. Probes and gates, never the clock.
@MainActor
@Suite("Workout pump (adversarial)", .tags(.feature), .timeLimit(.minutes(2)))
struct WorkoutPumpAdversarialTests {
    typealias Bench = PumpBench

    // MARK: Seeded storms against the same taps made one at a time

    /// `count` taps of every kind on rows the workout holds, one in eight on a row it does not.
    static func taps(seed: UInt64, in running: WorkoutState, count: Int = 36) -> [WorkoutEdit] {
        var generator = SplitMix64(seed: seed)
        let rows = running.exercises.enumerated().flatMap { index, exercise in exercise.sets.map { (index, $0.id) } }
        return (0 ..< count).map { _ in
            var (exercise, set) = rows[Int.random(in: 0 ..< rows.count, using: &generator)]
            if Int.random(in: 0 ..< 8, using: &generator) == 0 {
                exercise = Int.random(in: -1 ... 5, using: &generator)
            }
            let direction: SetRowSteppers.Direction = Bool.random(using: &generator) ? .increment : .decrement
            switch Int.random(in: 0 ..< 20, using: &generator) {
            case 0 ..< 2: return .select(exerciseIndex: exercise, setID: set)
            case 2 ..< 8: return .log(exerciseIndex: exercise, setID: set)
            case 8 ..< 10: return .unlog(exerciseIndex: exercise, setID: set)
            case 10 ..< 14: return .stepWeight(exerciseIndex: exercise, setID: set, direction)
            case 14 ..< 16: return .stepReps(exerciseIndex: exercise, setID: set, direction)
            case 16: return .repeatLast(exerciseIndex: exercise)
            case 17: return .addSet(exerciseIndex: exercise)
            default: return .jump(exerciseIndex: exercise)
            }
        }
    }

    /// What a run of taps came to.
    struct Outcome {
        let applied: [WorkoutEvent]
        let final: WorkoutState?
        let selection: WorkoutSelection?
    }

    /// Each tap made, applied and shown before the next: the page the lifter saw is the session's workout.
    static func oneAtATime(_ taps: [WorkoutEdit]) async throws -> Outcome {
        let bench = try await Bench.make()
        for tap in taps {
            bench.tap(tap)
            await bench.store.drain()
            await bench.settled()
        }
        bench.following.cancel()
        return await Outcome(
            applied: bench.session.applied,
            final: bench.session.current(),
            selection: bench.store.selection
        )
    }

    /// The same taps in bursts: every call waits, more taps arrive while it does, and the stream is let on
    /// some updates at a time, so the page is behind the answers for most of them.
    static func inAStorm(_ taps: [WorkoutEdit], seed: UInt64) async throws -> Outcome {
        let bench = try await Bench.make()
        await bench.session.holdEveryApply()
        await bench.session.keepStreamsBehind()
        var generator = SplitMix64(seed: seed ^ 0xA5A5)
        var next = 0
        while next < taps.count {
            bench.tap(taps[next])
            next += 1
            await bench.drainReleasing {
                for _ in 0 ..< Int.random(in: 0 ... 3, using: &generator) where next < taps.count {
                    bench.tap(taps[next])
                    next += 1
                }
                await bench.session.deliver(Int.random(in: 0 ... 2, using: &generator))
            }
            await bench.settled()
        }
        bench.following.cancel()
        return await Outcome(
            applied: bench.session.applied,
            final: bench.session.current(),
            selection: bench.store.selection
        )
    }

    @Test(
        "Taps made in bursts while calls wait and the page is behind come to what the same taps come to one at a time",
        arguments: Array(1 ... 16) as [UInt64]
    )
    func storm_isTheSameAsOneAtATime(seed: UInt64) async throws {
        let taps = Self.taps(seed: seed, in: EventBuilders.seedSession())
        let calm = try await Self.oneAtATime(taps)
        let storm = try await Self.inAStorm(taps, seed: seed)
        #expect(calm.applied.count >= 10, "the taps of this seed did too little to tell")
        let firstDifference = zip(calm.applied, storm.applied).enumerated().first { $0.element.0 != $0.element.1 }?
            .offset
        #expect(firstDifference == nil, "the events differ from number \(firstDifference ?? -1) on")
        #expect(calm.applied.count == storm.applied.count)
        let isSameWorkout = unchanged(storm.final, calm.final)
        #expect(isSameWorkout)
        #expect(calm.selection == storm.selection)
    }

    // MARK: Another hand between two taps (the reviewer's S-6 a)

    @Test("A change from elsewhere while a tap's call waits: the next tap is planned on the newest workout")
    func changeElsewhere_whileACallWaits() async throws {
        let bench = try await Bench.make()
        let (first, second) = (bench.set(0, 0), bench.set(0, 1))
        await bench.session.holdEveryApply()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: second, .increment))
        await bench.drainReleasing {
            // The watch logs the first set at 300 lb; the lifter, who has not seen it, taps its check and "+".
            _ = try? await bench.session.elsewhere(.setLogged(
                exerciseIndex: 0, setID: first, weight: .pounds(300), reps: .one, doneAt: Fixtures.now
            ))
            if await bench.session.applied.isEmpty {
                bench.tap(
                    .log(exerciseIndex: 0, setID: first),
                    .stepWeight(exerciseIndex: 0, setID: second, .increment)
                )
            }
        }
        let truth = try #require(await bench.settled())
        #expect(truth.exercises[0].sets[0].weight == .pounds(300), "the watch's set is not logged over")
        #expect(truth.exercises[0].sets[0].reps == .one)
        #expect(truth.exercises[0].sets[1].weight == .pounds(195), "two steps, each on the one before")
        #expect(truth.doneSets == 1)
        bench.following.cancel()
    }

    @Test("A change from elsewhere the page has shown is what the next tap starts from, with the stream behind")
    func changeElsewhere_shownBeforeTheNextTap() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.keepStreamsBehind()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.store.drain()
        try await bench.session.elsewhere(.setTargetChanged(
            exerciseIndex: 0,
            setID: first,
            weight: .pounds(300),
            reps: nil
        ))
        await bench.settled()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.store.drain()
        #expect(await bench.weight(0, 0) == "305")
        bench.following.cancel()
    }
}

extension WorkoutPumpAdversarialTests {
    // MARK: A refusal in the middle

    @Test("A refusal between two changes: the alert, the taps behind dropped, the page as the session, and on again")
    func refusal_inTheMiddle() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.keepStreamsBehind()
        await bench.session.refuse(calls: [2])
        bench.tap(
            .stepWeight(exerciseIndex: 0, setID: first, .increment),
            .stepWeight(exerciseIndex: 0, setID: first, .increment),
            .log(exerciseIndex: 0, setID: first),
            .jump(exerciseIndex: 3)
        )
        await bench.store.drain()
        #expect(bench.store.dialog == .editFailed)
        #expect(await bench.session.applied.count == 1, "the log and the jump behind the refusal were dropped")
        await bench.store.drain()
        #expect(await bench.session.applied.count == 1, "and stay dropped")
        await bench.settled()
        #expect(bench.store.model.page?.card?.rows.first.map { "\($0.weight) \($0.state)" } == "190 active")
        #expect(bench.store.selection == nil)

        bench.store.send(.dismissFailure)
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment), .log(exerciseIndex: 0, setID: first))
        await bench.store.drain()
        let truth = try #require(await bench.settled())
        #expect(truth.exercises[0].sets[0].weight == .pounds(195))
        #expect(truth.exercises[0].sets[0].isDone)
        #expect(bench.store.dialog == nil)
        bench.following.cancel()
    }

    @Test("A discard the session refuses: the taps that waited are gone, and the page answers again")
    func refusedDiscard_thePageAnswersAgain() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.refuseDiscard()
        bench.tap(.log(exerciseIndex: 0, setID: first))
        bench.store.send(.finish)
        bench.store.send(.discard)
        bench.tap(.log(exerciseIndex: 0, setID: first))
        await bench.store.drain()
        await bench.store.discard()
        #expect(bench.store.dialog == .discardFailed)
        #expect(await bench.session.applied.isEmpty)
        bench.store.send(.dismissFailure)
        #expect(bench.store.model.page?.isEnabled == true)
        bench.tap(.stepReps(exerciseIndex: 0, setID: bench.set(0, 1), .increment))
        await bench.store.drain()
        let truth = try #require(await bench.settled())
        #expect(truth.doneSets == 0, "the check tapped before Discard was applied after the discard was refused")
        #expect(await bench.session.applied.count == 2, "the second row chosen, then its reps")
        bench.following.cancel()
    }

    @Test("A change from elsewhere, with nothing behind: the next tap starts from it, however the answers fell")
    func changeElsewhere_withNothingBehind() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        for round in 1 ... 3 {
            bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
            await bench.store.drain()
            await bench.settled()
            await giveWay()
            let heavy = Weight.pounds(Decimal(300 * round))
            try await bench.session.elsewhere(.setTargetChanged(
                exerciseIndex: 0,
                setID: first,
                weight: heavy,
                reps: nil
            ))
            await bench.settled()
            bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
            await bench.store.drain()
            #expect(await bench.weight(0, 0) == "\(300 * round + 5)", "round \(round)")
            await bench.settled()
        }
        bench.following.cancel()
    }

    @Test("An answer that comes back after the page has shown it is not kept for the next tap")
    func answerAfterThePageShowedIt_isNotKept() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.holdEveryAnswer()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.drainReleasing {
            await eventually("the page to show the step") {
                bench.store.shown?.exercises[0].sets[0].weight == .pounds(190)
            }
        }
        await bench.session.holdEveryAnswer(false)
        try await bench.session.elsewhere(.setTargetChanged(
            exerciseIndex: 0,
            setID: first,
            weight: .pounds(300),
            reps: nil
        ))
        await bench.settled()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.store.drain()
        #expect(await bench.weight(0, 0) == "305", "one step from what the page showed")
        bench.following.cancel()
    }

    @Test("A tap on a workout that ended elsewhere, before the page heard of it, shows no alert")
    func endedElsewhere_beforeThePageHeard() async throws {
        let bench = try await Bench.make()
        await bench.session.keepStreamsBehind()
        try await bench.session.discard(endedAt: Fixtures.now)
        bench.tap(.log(exerciseIndex: 0, setID: bench.set(0, 0)))
        await bench.store.drain()
        #expect(bench.store.dialog == nil, "the workout ended by another hand: no change of the lifter's failed")
        #expect(bench.store.exit == nil, "the page has not heard yet")
        await bench.session.deliver()
        await eventually("the cover to close") { bench.store.exit != nil }
        #expect(bench.store.exit == .route(.discarded))
        #expect(bench.store.dialog == nil)
        await bench.following.value
    }
}
