import Foundation
@testable import LedgerDomain
import Testing

@Suite("Exercise", .tags(.domain))
struct ExerciseTests {
    @Test("Default steps: lb barbell 5, others 2.5; kg barbell 2.5, others 1.25 (rule 1, decision #9)")
    func equipment_defaultStep() {
        #expect(Equipment.barbell.defaultStep(in: .lb) == .pounds(5))
        #expect(Equipment.barbell.defaultStep(in: .kg) == .kilograms(2.5))
        // Decision #22 moved kettlebells to their bell-size gap; they are pinned in the next test.
        for equipment in Equipment.allCases where ![.barbell, .kettlebell].contains(equipment) {
            #expect(equipment.defaultStep(in: .lb) == .pounds(2.5))
            #expect(equipment.defaultStep(in: .kg) == .kilograms(1.25))
        }
    }

    @Test("Kettlebells step 5 lb / 2 kg, the gap between bell sizes (decision #22)")
    func kettlebell_defaultStep() {
        #expect(Equipment.kettlebell.defaultStep(in: .lb) == .pounds(5))
        #expect(Equipment.kettlebell.defaultStep(in: .kg) == .kilograms(2))
    }

    @Test("A kettlebell's missing unit rounds to the 2 kg / 5 lb step, landing on a real bell")
    func kettlebell_startLoadFallback_landsOnABell() {
        var bell = Fixtures.exercise(30, "Kettlebell Swing", .kettlebell, pounds: 35, kilograms: 16)
        bell.defaultStartLoad = [.lb: .pounds(35)]
        #expect(bell.startLoad(in: .kg) == .kilograms(16)) // 15.88 kg → 16
        bell.defaultStartLoad = [.kg: .kilograms(12)]
        #expect(bell.startLoad(in: .lb) == .pounds(25)) // 26.46 lb → 25
    }

    @Test("The start load is the unit's W0, else the other unit's rounded to this unit's step, else zero")
    func startLoad_fallsBack() {
        var exercise = Fixtures.inclineDB
        #expect(exercise.startLoad(in: .lb) == .pounds(50))
        #expect(exercise.startLoad(in: .kg) == .kilograms(22.5))
        exercise.defaultStartLoad = [.lb: .pounds(50)]
        #expect(exercise.startLoad(in: .kg) == .kilograms(22.5))
        exercise.defaultStartLoad = [.kg: .kilograms(20)]
        #expect(exercise.startLoad(in: .lb) == .pounds(45))
        exercise.defaultStartLoad = [:]
        #expect(exercise.startLoad(in: .lb) == .zero)
    }

    @Test("An exercise round-trips through JSON")
    func codable_roundTrip_preservesValue() throws {
        var exercise = Fixtures.bench
        exercise.secondaryMuscles = [.triceps, .shoulders]
        exercise.curatedAlternatives = [Fixtures.inclineDB.id]
        exercise.isCustom = true
        #expect(try JSONDecoder().decode(Exercise.self, from: JSONEncoder().encode(exercise)) == exercise)
    }
}
