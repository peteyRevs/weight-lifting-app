import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b criteria 13 to 27: the swap button, the sheet and its store, against the routes the lifter
/// and another hand can take. Ruling Q2 (no swap once a set of the exercise is logged) in every route; the
/// alternatives' rules on the shipped catalog; failures of the reads and of the send; double taps; a load
/// that answers late; the toggle (Q4); the cover after a swap; the bests a swap brings in. Written from the
/// contract before the implementer's tests and notes were read.
@MainActor
@Suite("Swap sheet and store (adversarial)", .tags(.feature), .timeLimit(.minutes(2)))
struct WorkoutSwapAdversarialTests {
    typealias Bench = SwapG2Bench

    static func reps(_ value: Int) throws -> Reps {
        try #require(Reps(value))
    }

    /// Another hand logs row `row` of exercise `exercise`.
    static func peerLogs(_ bench: Bench, _ exercise: Int, _ row: Int) async throws {
        try await bench.session.elsewhere(.setLogged(
            exerciseIndex: exercise,
            setID: bench.set(exercise, row),
            weight: .pounds(185),
            reps: reps(5),
            doneAt: Fixtures.now
        ))
    }

    // MARK: Q2 in every route

    @Test("Q2: a logged set hides the button and refuses the intent; un-logged elsewhere, it is back and swaps")
    func q2_loggedThenUndone() async throws {
        let bench = try await Bench.make()
        #expect(bench.card?.swap == "Swap exercise")
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: bench.set(0, 0))))
        await bench.settle()
        #expect(bench.card?.swap == nil, "no dead button once a set of the exercise is logged")
        let attempt = bench.store.swapAttempt
        bench.store.send(.openSwap)
        #expect(bench.store.dialog == nil)
        #expect(bench.store.swapAttempt == attempt)

        try await bench.session.elsewhere(.setUnlogged(exerciseIndex: 0, setID: bench.set(0, 0)))
        await bench.settle()
        #expect(bench.card?.swap == "Swap exercise")
        await bench.open()
        #expect(bench.use("Dumbbell Bench Press"))
        await bench.settle()
        #expect(bench.card?.title == "Dumbbell Bench Press")
        #expect(await bench.swapsApplied() == 1)
    }

    @Test("Q2: another hand logs a set while the sheet is up: the sheet goes, and its row then does nothing")
    func q2_peerLogsWhileSheetIsUp() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let row = try #require(bench.sheet?.rows.first)
        try await Self.peerLogs(bench, 0, 0)
        await bench.settle()
        #expect(bench.store.dialog == nil, "criterion 25")
        bench.store.send(.edit(row.choose))
        await bench.settle()
        #expect(await bench.swapsApplied() == 0)
        #expect(bench.card?.title == "Barbell Bench Press")
    }

    @Test("Q2: a set logged by another hand between Use and its turn: the swap comes to nothing, silently")
    func q2_peerLogsBetweenUseAndItsTurn() async throws {
        let bench = try await Bench.make()
        await bench.open()
        await bench.session.holdEveryApply()
        // A tap made before "Use", still waiting when the other hand logs.
        bench.store.send(.edit(.stepWeight(exerciseIndex: 0, setID: bench.set(0, 1), .increment)))
        #expect(bench.use("Dumbbell Bench Press"))
        let draining = Task { await bench.store.drain() }
        let waiting = bench.session.waiting
        await eventually("the step to wait") { waiting.value == 1 }
        try await Self.peerLogs(bench, 0, 0)
        await bench.session.holdEveryApply(false)
        await bench.session.release()
        await draining.value
        await bench.settle()
        #expect(await bench.swapsApplied() == 0, "criterion 19: a done set now")
        #expect(bench.store.dialog == nil, "no alert: nothing was refused")
        #expect(bench.card?.title == "Barbell Bench Press")
        let live = await bench.session.current()
        #expect(live?.exercises[0].sets[1].weight == .pounds(190), "the tap before Use was applied first")
    }

    @Test("Q2: a log tapped just before Use is applied first, and the swap after it comes to nothing")
    func q2_ownLogQueuedBeforeUse() async throws {
        let bench = try await Bench.make()
        await bench.open()
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: bench.set(0, 0))))
        #expect(bench.use("Dumbbell Bench Press"))
        await bench.settle()
        #expect(await bench.swapsApplied() == 0)
        let live = await bench.session.current()
        #expect(live?.exercises[0].sets[0].isDone == true)
        #expect(live?.exercises[0].name == "Barbell Bench Press")
    }

    // MARK: Alternatives on the shipped catalog

    @Test("Bench with Dumbbell Bench and Incline DB Press in the workout: Q9 leaves them out, curated first")
    func alternatives_benchExcludingTheWorkout() async throws {
        let workout = try SwapG2Catalog.workout([
            "Barbell Bench Press", "Incline DB Press", "Chest-Supported Row", "Dumbbell Bench Press",
            "Cable Lateral Raise"
        ])
        let bench = try await Bench.make(workout)
        await bench.open()
        let names = bench.sheet?.rows.map(\.name) ?? []
        #expect(names.count == 8)
        #expect(Array(names.prefix(3)) == ["Smith Machine Bench Press", "Weighted Dip", "Machine Chest Press"])
        #expect(!names.contains("Dumbbell Bench Press"))
        #expect(!names.contains("Incline DB Press"))
        #expect(!names.contains("Barbell Bench Press"))
        let lastReads = await bench.stats.lastCalls
        #expect(lastReads.count == names.count, "criterion 17: one last-session read for each shown row")
    }

    @Test("A curated alternative the catalog no longer holds is skipped; the rows still fill to 8")
    func alternatives_curatedGone() async throws {
        let catalog = try SwapG2Catalog.all().filter { $0.name != "Smith Machine Bench Press" }
        let bench = try await Bench.make(catalog: catalog)
        await bench.open()
        let names = bench.sheet?.rows.map(\.name) ?? []
        #expect(names.count == 8)
        #expect(!names.contains("Smith Machine Bench Press"))
        #expect(names.first == "Dumbbell Bench Press")
    }

    @Test("Nothing to offer: the exercise is not stored, the catalog is empty, or all are in the workout")
    func alternatives_nothingToOffer() async throws {
        var unknown = try SwapG2Catalog.workout()
        unknown.exercises[0].exerciseID = ExerciseID(EventBuilders.uuid(0xDEAD))
        let bench = try SwapG2Catalog.named("Barbell Bench Press")
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press")
        var both = try SwapG2Catalog.workout()
        both.exercises[1].exerciseID = dumbbell.id
        both.exercises[1].name = dumbbell.name
        var onlyBench = bench
        onlyBench.curatedAlternatives = [dumbbell.id]
        let cases: [(WorkoutState, [Exercise]?)] = try [
            (unknown, nil),
            (SwapG2Catalog.workout(), []),
            (both, [onlyBench, dumbbell])
        ]
        for (workout, catalog) in cases {
            let made = try await Bench.make(workout, catalog: catalog)
            await made.open()
            let sheet = try #require(made.sheet)
            #expect(sheet.message == "No alternatives for this exercise.")
            #expect(sheet.rows.isEmpty)
            #expect(sheet.toggle == nil)
            #expect(sheet.line == "Same movement pattern.")
            #expect(sheet.title == "Swap exercise")
            made.following.cancel()
        }
    }
}
