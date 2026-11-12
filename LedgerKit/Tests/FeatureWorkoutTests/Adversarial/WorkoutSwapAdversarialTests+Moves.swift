import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b: the workout moving under the sheet (criteria 25, Q9) and the bests a swap brings in (27).
extension WorkoutSwapAdversarialTests {
    // MARK: The workout moves under the sheet

    @Test("Ended elsewhere while the sheet is up: the sheet and the cover close")
    func endedElsewhere() async throws {
        let bench = try await Bench.make()
        await bench.open()
        try await bench.session.elsewhere(.discarded(endedAt: Fixtures.now))
        await observed("the cover to close") { bench.store.exit != nil }
        #expect(bench.store.dialog == nil)
    }

    @Test("The session's updates end while the sheet is up: the sheet goes with the workout")
    func updatesEnd() async throws {
        let bench = try await Bench.make()
        await bench.open()
        await bench.session.endStreams()
        await observed("the failed screen") {
            if case .failed = bench.store.workout {
                return true
            }
            return false
        }
        #expect(bench.store.dialog == nil)
    }

    @Test("Another hand swaps the shown exercise while the sheet is up: the sheet goes, its row does nothing")
    func peerSwapsTheShownExercise() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let row = try #require(bench.sheet?.rows.first { $0.name == "Weighted Dip" })
        let other = try SwapG2Catalog.named("Machine Chest Press")
        try await bench.session.elsewhere(.exerciseSwapped(
            exerciseIndex: 0, exerciseID: other.id, name: other.name, alsoUpdateProgram: false
        ))
        await bench.settle()
        #expect(bench.store.dialog == nil)
        bench.store.send(.edit(row.choose))
        await bench.settle()
        #expect(bench.card?.title == "Machine Chest Press")
    }

    /// Q9 says one exercise never appears twice in a workout. The list leaves out the workout's exercises as
    /// they were when it was read; nothing checks again at "Use". Another hand (the watch, F17) that swaps a
    /// later exercise into one of the offered rows meanwhile leaves the row live, and "Use" then puts the same
    /// exercise in two places.
    @Test("F10-S8b-G2-1: another hand puts an offered exercise in the workout; Use makes no duplicate")
    func peerTakesAnOfferedExercise_useDuplicates() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press")
        try await bench.session.elsewhere(.exerciseSwapped(
            exerciseIndex: 3, exerciseID: dumbbell.id, name: dumbbell.name, alsoUpdateProgram: false
        ))
        await bench.settle()
        let offered = bench.sheet?.rows.contains { $0.id == dumbbell.id } ?? false
        _ = bench.use(dumbbell.name)
        await bench.settle()
        let ids = await bench.session.current()?.exercises.map(\.exerciseID) ?? []
        #expect(Set(ids).count == ids.count, "Q9: one exercise twice in the workout (row still offered: \(offered))")
    }

    // MARK: Bests for the exercise a swap brings in (criterion 27)

    @Test("The bests of the new exercise are read once and merged; swapping back reads nothing more")
    func bests_readOnce() async throws {
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press").id
        let bench = try await Bench.make {
            await $0.set(bests: PersonalRecords.Bests(e1RM: [dumbbell: .pounds(80)]))
        }
        await bench.store.readBests()
        #expect(await bench.stats.bestsCalls.count == 1)
        await bench.open()
        #expect(bench.use("Dumbbell Bench Press"))
        await bench.settle()
        #expect(bench.store.unreadBests == [dumbbell])
        await bench.store.readSwappedBests()
        await bench.store.readSwappedBests()
        #expect(await bench.stats.bestsCalls.count == 2)
        #expect(await bench.stats.bestsCalls.last == [dumbbell])
        guard case let .loaded(bests) = bench.store.bests else {
            Issue.record("the bests are loaded")
            return
        }
        #expect(bests.e1RM[dumbbell] == .pounds(80))

        await bench.open()
        #expect(bench.use("Barbell Bench Press"), "back to the original")
        await bench.settle()
        #expect(bench.store.unreadBests.isEmpty)
        await bench.store.readSwappedBests()
        #expect(await bench.stats.bestsCalls.count == 2, "the original's bests were read with the first")
    }

    @Test("A failed read of the new exercise's bests is not retried, and nothing is shown")
    func bests_failureNotRetried() async throws {
        let bench = try await Bench.make()
        await bench.store.readBests()
        await bench.stats.failBests()
        await bench.open()
        #expect(bench.use("Dumbbell Bench Press"))
        await bench.settle()
        await bench.store.readSwappedBests()
        #expect(bench.store.unreadBests.isEmpty)
        await bench.store.readSwappedBests()
        #expect(await bench.stats.bestsCalls.count == 2)
        #expect(bench.store.dialog == nil)
    }
}
