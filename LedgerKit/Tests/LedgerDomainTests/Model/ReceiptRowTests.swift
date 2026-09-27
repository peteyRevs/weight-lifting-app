import Foundation
@testable import LedgerDomain
import Testing

@Suite("ReceiptRow", .tags(.domain))
struct ReceiptRowTests {
    @Test("Target is the prescription before \" · \" (rule 30)")
    func target_isSchemeWithoutRPE() throws {
        let exercise = try Fixtures.workoutExercise(
            Fixtures.bench, index: 0, sets: [], targetSets: 5, targetReps: 5, targetLoad: .pounds(185)
        )
        #expect(ReceiptRow(exercise: exercise, units: .lb).target == "5 × 5 @ 185 lb")
        #expect(ReceiptRow(exercise: exercise, units: .kg).target == "5 × 5 @ 83.9 kg")
    }

    @Test("Identical consecutive done sets group into one \"n × w×r\" chip (rule 30)")
    func actual_groupsRuns() throws {
        let sets = (0 ..< 5).map { Fixtures.set($0, pounds: 185, reps: 5) }
        let row = try ReceiptRow(exercise: Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets), units: .lb)
        #expect(row.actual == ["5 × 185×5"])
        #expect(row.name == "Barbell Bench Press")
    }

    @Test("A change of weight or reps starts a new chip; single sets have no count")
    func actual_newRunOnChange() throws {
        let sets = [
            Fixtures.set(0, pounds: 185, reps: 5),
            Fixtures.set(1, pounds: 185, reps: 5),
            Fixtures.set(2, pounds: 185, reps: 4),
            Fixtures.set(3, pounds: 185, reps: 5),
            Fixtures.set(4, pounds: 155, reps: 5, kind: .drop)
        ]
        let row = try ReceiptRow(exercise: Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets), units: .lb)
        #expect(row.actual == ["2 × 185×5", "185×4", "185×5", "155×5"])
    }

    @Test("Undone sets are skipped, and an exercise with none done shows \"—\"")
    func actual_noneDone_isDash() throws {
        let partly = [Fixtures.set(0, pounds: 50, reps: 10), Fixtures.set(1, pounds: 50, reps: 10, done: false)]
        let none = [Fixtures.set(2, pounds: 50, reps: 10, done: false)]
        let partlyRow = try ReceiptRow(
            exercise: Fixtures.workoutExercise(Fixtures.inclineDB, index: 0, sets: partly),
            units: .lb
        )
        let noneRow = try ReceiptRow(
            exercise: Fixtures.workoutExercise(Fixtures.inclineDB, index: 1, sets: none),
            units: .lb
        )
        #expect(partlyRow.actual == ["50×10"])
        #expect(noneRow.actual == ["—"])
    }

    @Test("Chips use the display unit's number format")
    func actual_kilograms_printsKilogramNumbers() throws {
        let sets = try [LoggedSet(
            id: SetID(Fixtures.uuid(1)),
            weight: .kilograms(62.5),
            reps: Fixtures.reps(3),
            kind: .working,
            doneAt: Fixtures.now
        )]
        let row = try ReceiptRow(exercise: Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets), units: .kg)
        #expect(row.actual == ["62.5×3"])
    }
}
