import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b: the cover after a swap (criterion 18, Q5, Q7, decision #22).
extension WorkoutSwapAdversarialTests {
    // MARK: The cover after a swap

    @Test("After Bench → Dumbbell Bench (never done): name, No history yet, no Repeat, rows and TARGET at 15")
    func cover_afterSwap_noHistory() async throws {
        let bench = try await Bench.make()
        let remainingBefore = bench.page?.remaining?.rows.map(\.name)
        await bench.open()
        let row = try #require(bench.sheet?.rows.first { $0.name == "Dumbbell Bench Press" })
        #expect(row.detail == "Dumbbell · 15 lb")
        #expect(bench.use(row.name))
        await bench.settle()
        let card = try #require(bench.card)
        #expect(card.title == "Dumbbell Bench Press")
        #expect(card.eyebrow == "Exercise 1 of 5")
        #expect(card.last == "No history yet")
        #expect(card.repeatLast == nil)
        #expect(card.rows.allSatisfy { $0.weight == "15" })
        #expect(card.target.contains("@ 15 lb"), "Q5: \(card.target)")
        #expect(card.swap == "Swap exercise", "still no set logged")
        #expect(card.steppers?.setID == bench.set(0, 0), "the shown row stays the first undone row")
        #expect(card.steppers?.weightStep == "2.5 LB", "the dumbbell step")
        #expect(bench.page?.remaining?.rows.map(\.name) == remainingBefore)
    }

    @Test("After a swap onto an exercise done before: its Last line, Repeat, and its load on the rows")
    func cover_afterSwap_withHistory() async throws {
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press").id
        let last = LastPerformance(
            date: Fixtures.now.addingTimeInterval(-7 * 86400), sets: 3, reps: 8, load: .pounds(62)
        )
        let bench = try await Bench.make { await $0.set(last: last, for: dumbbell) }
        await bench.open()
        let row = try #require(bench.sheet?.rows.first { $0.name == "Dumbbell Bench Press" })
        #expect(row.detail == "Dumbbell · 62.5 lb", "62 rounded to the 2.5 lb step")
        #expect(bench.use(row.name))
        await bench.settle()
        let card = try #require(bench.card)
        #expect(card.last.contains("@ 62 lb") || card.last.contains("@ 62.5 lb"), "\(card.last)")
        #expect(card.repeatLast != nil)
        #expect(card.rows.allSatisfy { $0.weight == "62.5" }, "what the sheet showed is what Use applied")
        #expect(card.steppers?.weightStep == "2.5 LB")
    }

    @Test("Kettlebell in kilograms: the row says 12 kg, the rows take 12, and + moves by 2 kg", arguments: [
        Units.kg, .lb
    ])
    func cover_kettlebell(units: Units) async throws {
        let workout = try SwapG2Catalog.workout(
            ["Goblet Squat", "Incline DB Press", "Chest-Supported Row", "Lat Pulldown", "Cable Lateral Raise"],
            units: units
        )
        let bench = try await Bench.make(workout)
        await bench.open()
        let row = try #require(bench.sheet?.rows.first { $0.name == "Kettlebell Goblet Squat" })
        let (load, step, next) = units == .kg ? ("12", "2 KG", "14") : ("25", "5 LB", "30")
        #expect(row.detail == "Kettlebell · \(load) \(units == .kg ? "kg" : "lb")")
        #expect(bench.use(row.name))
        await bench.settle()
        #expect(bench.card?.rows.first?.weight == load)
        #expect(bench.card?.steppers?.weightStep == step)
        bench.store.send(.edit(.stepWeight(exerciseIndex: 0, setID: bench.set(0, 0), .increment)))
        await bench.settle()
        #expect(bench.card?.rows.first?.weight == next)
    }

    @Test("A bodyweight row with no history reads Bodyweight alone (Q7), and Use sets its rows to 0")
    func bodyweight_row() async throws {
        let bench = try await Bench.make()
        await bench.open()
        let row = try #require(bench.sheet?.rows.first { $0.name == "Decline Push-Up" })
        #expect(row.detail == "Bodyweight")
        #expect(bench.use(row.name))
        await bench.settle()
        #expect(bench.card?.rows.allSatisfy { $0.weight == "0" } == true)
    }
}
