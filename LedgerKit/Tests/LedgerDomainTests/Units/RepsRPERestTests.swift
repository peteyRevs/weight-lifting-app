import Foundation
@testable import LedgerDomain
import Testing

@Suite("Reps, RPE and RestDuration", .tags(.domain))
struct RepsRPERestTests {
    struct LabelRow: Sendable, CustomStringConvertible {
        let seconds: Int
        let label: String

        var description: String {
            "\(seconds) s → \(label)"
        }

        static let all: [LabelRow] = [
            LabelRow(seconds: 30, label: "30s"),
            LabelRow(seconds: 45, label: "45s"),
            LabelRow(seconds: 60, label: "1 min"),
            LabelRow(seconds: 75, label: "1:15"),
            LabelRow(seconds: 90, label: "1:30"),
            LabelRow(seconds: 120, label: "2 min"),
            LabelRow(seconds: 150, label: "2:30"),
            LabelRow(seconds: 195, label: "3:15"),
            LabelRow(seconds: 285, label: "4:45"),
            LabelRow(seconds: 300, label: "5 min")
        ]
    }

    @Test("Reps must be at least 1; clamping lifts lower values to 1 (rule 2)")
    func reps_belowOne_isRejectedOrClampedToOne() {
        #expect(Reps(0) == nil)
        #expect(Reps(-3) == nil)
        #expect(Reps(1)?.value == 1)
        #expect(Reps(40)?.value == 40)
        #expect(Reps(clamping: 0) == .one)
        #expect(Reps(clamping: 7).value == 7)
        #expect(Reps.one < Reps(clamping: 2))
    }

    @Test("RPE accepts 5…10 in 0.5 steps only (rule 3)", arguments: ["4.5", "4.75", "5.25", "10.5", "8.1", "-8"])
    func rpe_rejectsOutOfRange(text: String) {
        #expect(RPE(dec(text)) == nil)
    }

    @Test("RPE values, labels and ordering")
    func rpe_valuesAndLabels() throws {
        let eight = try Fixtures.rpe(8)
        let eightAndHalf = try Fixtures.rpe(8.5)
        #expect(eight.value == 8)
        #expect(eight.label == "8")
        #expect(eightAndHalf.label == "8.5")
        #expect(try Fixtures.rpe(5).label == "5")
        #expect(try Fixtures.rpe(10).label == "10")
        #expect(eight < eightAndHalf)
        #expect(try Fixtures.rpe(dec("8.0")) == eight)
        #expect(try Fixtures.rpe(dec("8.0")).hashValue == eight.hashValue)
    }

    @Test("Deload lowers RPE by 2 and never below 5 (rule 12)")
    func rpe_deloaded() throws {
        #expect(try Fixtures.rpe(8).deloaded() == Fixtures.rpe(6))
        #expect(try Fixtures.rpe(6.5).deloaded() == Fixtures.rpe(5))
        #expect(try Fixtures.rpe(5).deloaded() == Fixtures.rpe(5))
    }

    @Test("Rest accepts 30…300 s in 15 s steps only (rule 3)", arguments: [0, 15, 29, 100, 305, 315, -30])
    func rest_rejectsOutOfRange(seconds: Int) {
        #expect(RestDuration(seconds: seconds) == nil)
    }

    @Test("Rest labels follow rule 39", arguments: LabelRow.all)
    func rest_label(row: LabelRow) throws {
        #expect(try Fixtures.rest(row.seconds).label == row.label)
    }

    @Test("Rest exposes its Duration, orders by seconds and defaults to 90 s")
    func rest_durationAndDefault() throws {
        #expect(RestDuration.defaultRest.seconds == 90)
        #expect(try Fixtures.rest(150).duration == .seconds(150))
        #expect(try Fixtures.rest(60) < Fixtures.rest(75))
    }

    @Test("Reps, RPE and rest encode as bare values and re-validate when decoded")
    func codable_bareValuesValidated() throws {
        let decoder = JSONDecoder()
        #expect(try Fixtures.json(Fixtures.reps(5)) == "5")
        #expect(try Fixtures.json(Fixtures.rpe(8.5)) == "8.5")
        #expect(try Fixtures.json(Fixtures.rest(90)) == "90")
        #expect(try decoder.decode(Reps.self, from: Data("5".utf8)) == Fixtures.reps(5))
        #expect(try decoder.decode(RPE.self, from: Data("8.5".utf8)) == Fixtures.rpe(8.5))
        #expect(try decoder.decode(RestDuration.self, from: Data("90".utf8)) == Fixtures.rest(90))
        #expect(throws: DecodingError.self) { try decoder.decode(Reps.self, from: Data("0".utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(RPE.self, from: Data("4.5".utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(RestDuration.self, from: Data("100".utf8)) }
    }
}
