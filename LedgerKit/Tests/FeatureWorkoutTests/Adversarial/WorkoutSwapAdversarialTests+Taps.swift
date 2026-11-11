import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b: double taps, reads that answer late, and the toggle (Q4).
extension WorkoutSwapAdversarialTests {
    // MARK: One swap per tap; loads that answer late

    @Test("A double tap on Use, or two rows in a row, applies one swap: the first")
    func use_doubleTap() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let rows = try #require(bench.sheet?.rows)
        bench.store.send(.edit(rows[0].choose))
        bench.store.send(.edit(rows[0].choose))
        bench.store.send(.edit(rows[1].choose))
        await bench.settle()
        #expect(await bench.swapsApplied() == 1)
        #expect(bench.card?.title == rows[0].name)
    }

    @Test("A second Swap exercise while the sheet is up makes no second read")
    func open_twice() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let attempt = bench.store.swapAttempt
        bench.store.send(bench.store.cardOpensSwap)
        #expect(bench.store.swapAttempt == attempt)
        #expect(bench.sheet?.rows.count == 8)
    }

    @Test("Use, then Swap exercise again before the swap lands: that sheet goes when it lands, nothing twice")
    func use_thenReopenBeforeItLands() async throws {
        let bench = try await Bench.make()
        await bench.open()
        #expect(bench.use("Dumbbell Bench Press"))
        bench.store.send(bench.store.cardOpensSwap)
        await bench.store.loadSwap()
        let stale = bench.sheet?.rows.first { $0.name == "Machine Chest Press" }
        await bench.settle()
        #expect(bench.store.dialog == nil, "criterion 25: another exercise in its place")
        if let stale {
            bench.store.send(.edit(stale.choose))
            await bench.settle()
        }
        #expect(await bench.swapsApplied() == 1)
        #expect(bench.card?.title == "Dumbbell Bench Press")
    }

    @Test("An older attempt's read that answers last (with a failure) is dropped")
    func load_olderAttemptAnswersLast() async throws {
        let bench = try await Bench.make()
        await bench.exercises.holdNextAll(throwing: true)
        bench.store.send(bench.store.cardOpensSwap)
        let first = Task { await bench.store.loadSwap() }
        await bench.exercises.waitUntilHeld()
        bench.store.send(.swap(.cancel))
        await bench.open()
        #expect(bench.sheet?.rows.count == 8)
        await bench.exercises.release()
        await first.value
        #expect(bench.sheet?.rows.count == 8)
        #expect(bench.sheet?.message == nil)
    }

    @Test("The same attempt's read started again: the first answer shows, the late failure is dropped")
    func load_sameAttemptTwice() async throws {
        let bench = try await Bench.make()
        await bench.exercises.holdNextAll(throwing: true)
        bench.store.send(bench.store.cardOpensSwap)
        let first = Task { await bench.store.loadSwap() }
        await bench.exercises.waitUntilHeld()
        await bench.store.loadSwap()
        #expect(bench.sheet?.rows.count == 8)
        await bench.exercises.release()
        await first.value
        #expect(bench.sheet?.rows.count == 8)
        #expect(bench.sheet?.message == nil)
    }

    // MARK: The toggle (Q4)

    @Test("The toggle: hidden ad hoc; opens on with a program change; turned off, the change goes")
    func toggle_rules() async throws {
        let adHoc = try await Bench.make(SwapG2Catalog.workout(adHoc: true))
        await adHoc.open()
        #expect(adHoc.sheet?.toggle == nil)
        #expect(adHoc.sheet?.rows.isEmpty == false)
        adHoc.following.cancel()

        let bench = try await Bench.make()
        await bench.open()
        #expect(bench.sheet?.toggle == SwapSheetModel.Toggle(label: "Also update program", isOn: false))
        bench.store.send(.swap(.updateProgram(true)))
        #expect(bench.sheet?.toggle?.isOn == true)
        #expect(bench.use("Dumbbell Bench Press"))
        await bench.settle()
        let slot = try #require(bench.running.exercises[0].slotID)
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press").id
        #expect(await bench.session.current()?.programUpdates[slot] == dumbbell)

        await bench.open()
        #expect(bench.sheet?.toggle?.isOn == true, "Q4: opens on while the slot carries a change")
        bench.store.send(.swap(.updateProgram(false)))
        #expect(bench.use("Machine Chest Press"))
        await bench.settle()
        #expect(await bench.session.current()?.programUpdates[slot] == nil, "Q4: off removes it")
        #expect(bench.card?.title == "Machine Chest Press")
    }

    @Test("The toggle turned on while the read is out is what the rows then carry")
    func toggle_whileLoading() async throws {
        let bench = try await Bench.make()
        bench.store.send(bench.store.cardOpensSwap)
        bench.store.send(.swap(.updateProgram(true)))
        await bench.store.loadSwap()
        #expect(bench.sheet?.toggle?.isOn == true)
        guard case let .swap(_, _, alsoUpdateProgram) = bench.sheet?.rows.first?.choose else {
            Issue.record("a row sends a swap")
            return
        }
        #expect(alsoUpdateProgram)
    }
}
