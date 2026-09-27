import Foundation
@testable import LedgerDomain
import Testing

@Suite("Prescription", .tags(.domain))
struct PrescriptionTests {
    @Test("The target line reads \"5 × 5 @ 185 lb · RPE 8\" (rule 14)")
    func targetLine_specFormat() throws {
        let prescription = try Prescription(
            load: .pounds(185), sets: 5, reps: 5, rpe: Fixtures.rpe(8), rest: Fixtures.rest(150),
            step: .pounds(5), progression: .linear, isHeld: false, isDeload: false
        )
        #expect(prescription.targetLine(units: .lb) == "5 × 5 @ 185 lb · RPE 8")
        #expect(prescription.targetLine(units: .kg) == "5 × 5 @ 83.9 kg · RPE 8")
        let half = try Prescription(
            load: .kilograms(52.5), sets: 3, reps: 10, rpe: Fixtures.rpe(8.5), rest: Fixtures.rest(90),
            step: .kilograms(2.5), progression: .double, isHeld: true, isDeload: false
        )
        #expect(half.targetLine(units: .kg) == "3 × 10 @ 52.5 kg · RPE 8.5")
    }
}
