import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b criteria 22 and 23: reads and a send that fail.
extension WorkoutSwapAdversarialTests {
    // MARK: Failures

    @Test("all() fails: the failed line, no row, no toggle; Cancel closes; opening again reads again")
    func failure_allThrows() async throws {
        let bench = try await Bench.make()
        await bench.exercises.failAll()
        await bench.open()
        let sheet = try #require(bench.sheet)
        #expect(sheet.message == "Couldn't load alternatives.")
        #expect(sheet.rows.isEmpty)
        #expect(sheet.toggle == nil)
        bench.store.send(.swap(.cancel))
        #expect(bench.store.dialog == nil)
        await bench.exercises.failAll(false)
        await bench.open()
        #expect(bench.sheet?.rows.count == 8)
        #expect(bench.sheet?.message == nil)
        #expect(await bench.exercises.allCalls == 2)
    }

    @Test("exercise(id:) fails: the failed line")
    func failure_exerciseThrows() async throws {
        let bench = try await Bench.make()
        await bench.exercises.failExercise()
        await bench.open()
        #expect(bench.sheet?.message == "Couldn't load alternatives.")
        #expect(bench.sheet?.rows.isEmpty == true)
    }

    @Test("One last-session read fails: the whole sheet fails, never a guessed load")
    func failure_oneLastPerformanceThrows() async throws {
        let target = try SwapG2Catalog.named("Weighted Dip").id
        let bench = try await Bench.make { await $0.failLast(for: target) }
        await bench.open()
        #expect(bench.sheet?.message == "Couldn't load alternatives.")
        #expect(bench.sheet?.rows.isEmpty == true)
    }

    @Test("A refused swap: the alert, the taps behind it dropped, the card as it was, no program change")
    func failure_swapRefused() async throws {
        let bench = try await Bench.make()
        await bench.open()
        bench.store.send(.swap(.updateProgram(true)))
        await bench.session.refuse(calls: [1])
        #expect(bench.use("Dumbbell Bench Press"))
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: bench.set(0, 0))))
        await bench.store.drain()
        await bench.session.deliver()
        #expect(bench.store.dialog == .editFailed)
        #expect(await bench.session.applied.isEmpty, "the log behind the refused swap is dropped")
        #expect(bench.card?.title == "Barbell Bench Press")
        let live = await bench.session.current()
        #expect(live?.programUpdates.isEmpty == true)
    }
}
