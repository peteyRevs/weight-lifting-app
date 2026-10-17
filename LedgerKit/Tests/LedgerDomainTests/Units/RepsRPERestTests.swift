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

// MARK: - Clamping initializers (F11 slice S1: the Day editor's steppers)

extension RepsRPERestTests {
    @Test("RPE(clamping:) holds a value to 5…10 and rounds it to the nearest half, a tie going up (rule 3)")
    func rpeClampingInitializer_roundsToTheHalfAndStaysInRange() {
        let rpe = ["4.5": 5, "5": 5, "7.2": 7, "7.25": 7.5, "7.3": 7.5, "7.74": 7.5, "7.75": 8, "9.99": 10, "10.5": 10]
            as [String: Decimal]
        for (text, expected) in rpe {
            #expect(RPE(clamping: dec(text)).value == expected, "RPE \(text)")
        }
        #expect(RPE(clamping: -8).value == 5)
        #expect(RPE(clamping: .greatestFiniteMagnitude).value == 10)
        #expect(RPE(clamping: .nan).value == 5, "a NaN sorts below every number")
        #expect(RPE.step == dec("0.5"))
        for halves in 10 ... 20 {
            let value = Decimal(halves) / 2
            #expect(RPE(clamping: value) == RPE(value), "a valid RPE is kept: \(value)")
        }
    }

    @Test("RestDuration(clampingSeconds:) holds a value to 30…300 s and rounds it to the nearest 15 (rule 3)")
    func restClampingInitializer_roundsToFifteenAndStaysInRange() {
        let rest = [-30: 30, 0: 30, 29: 30, 30: 30, 37: 30, 38: 45, 52: 45, 53: 60, 100: 105, 292: 285, 293: 300]
        for (seconds, expected) in rest {
            #expect(RestDuration(clampingSeconds: seconds).seconds == expected, "\(seconds) s")
        }
        #expect(RestDuration(clampingSeconds: 315).seconds == 300)
        #expect(RestDuration(clampingSeconds: .max).seconds == 300)
        #expect(RestDuration(clampingSeconds: .min).seconds == 30)
        #expect(RestDuration.stepSeconds == 15)
        for seconds in -20 ... 340 {
            let clamped = RestDuration(clampingSeconds: seconds)
            #expect(RestDuration(seconds: clamped.seconds) == clamped, "\(seconds) s gives a rest the model accepts")
            #expect(abs(clamped.seconds - min(max(seconds, 30), 300)) <= 7, "\(seconds) s goes to the nearest step")
        }
        for seconds in stride(from: 30, through: 300, by: 15) {
            #expect(RestDuration(clampingSeconds: seconds).seconds == seconds, "a valid rest is kept")
        }
    }
}
