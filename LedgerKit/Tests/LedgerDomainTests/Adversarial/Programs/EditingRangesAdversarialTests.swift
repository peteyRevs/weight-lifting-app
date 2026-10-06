import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 13's "no change in behaviour": the three ranges of `Slot`, now public constants, are the
/// ranges `Slot.init` accepted before the slice, and the two new clamping initializers agree with the
/// failable ones on every valid value and hold every other value in range (criterion 7).
@Suite("Slot ranges and clamping initializers (adversarial)", .tags(.domain))
struct EditingRangesAdversarialTests {
    /// Whether `Slot.init` accepts these three numbers, with everything else valid.
    static func accepts(sets: Int = 3, reps: Int = 1, repsHi: Int = 40) -> Bool {
        (try? Fixtures.slot(Fixtures.bench, id: 1, sets: sets, reps: reps, repsHi: repsHi)) != nil
    }
}

extension EditingRangesAdversarialTests {
    @Test("The public ranges are rule 3's sets 1…12 and rule 2's reps 1…30 and top of range 2…40.")
    func ranges_areTheRules() {
        #expect(Slot.setsRange == 1 ... 12)
        #expect(Slot.repsRange == 1 ... 30)
        #expect(Slot.repsHiRange == 2 ... 40)
    }

    @Test("Slot.init accepts exactly the values of each range, as it did before the ranges were constants.")
    func slotInit_acceptsExactlyTheRanges() {
        var tally = Tally()
        for value in -60 ... 60 {
            tally.check(Self.accepts(sets: value) == (1 ... 12).contains(value), "sets \(value)")
            tally.check(Self.accepts(reps: value) == (1 ... 30).contains(value), "reps \(value)")
            tally.check(Self.accepts(repsHi: value) == (2 ... 40).contains(value), "top \(value)")
        }
        #expect(tally.passed, tally.summary)
    }

    @Test("Slot.init still throws the range it checked first: sets, then reps, then the top, then the top above reps.")
    func slotInit_throwsInTheSameOrder() {
        #expect(throws: SlotValidationError.setsOutOfRange(13)) {
            try Fixtures.slot(Fixtures.bench, id: 1, sets: 13, reps: 31, repsHi: 41)
        }
        #expect(throws: SlotValidationError.repsOutOfRange(31)) {
            try Fixtures.slot(Fixtures.bench, id: 1, sets: 12, reps: 31, repsHi: 41)
        }
        #expect(throws: SlotValidationError.repsHiOutOfRange(41)) {
            try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 30, repsHi: 41)
        }
        #expect(throws: SlotValidationError.repsHiNotAboveReps(reps: 30, repsHi: 30)) {
            try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 30, repsHi: 30)
        }
        #expect(throws: SlotValidationError.setsOutOfRange(0)) {
            try Fixtures.slot(Fixtures.bench, id: 1, sets: 0, reps: 0, repsHi: 1)
        }
    }

    @Test("RPE(clamping:) is RPE(_:) for each of the eleven valid values, and its step is a half.")
    func rpeClamping_validValues_agreeWithTheFailableInitializer() {
        for halves in 10 ... 20 {
            let value = EditAdv.rpe(halves: halves)
            #expect(RPE(clamping: value) == RPE(value), "RPE \(value)")
        }
        #expect(RPE.step == dec("0.5"))
    }

    @Test("RPE(clamping:) of every hundredth from −5 to 15 is the nearest half in 5…10, half way going up.")
    func rpeClamping_everyHundredth_isTheNearestHalfInRange() {
        var tally = Tally()
        for hundredths in -500 ... 1500 {
            let value = RPE(clamping: EditAdv.decimal(hundredths: hundredths)).value
            let expected = EditAdv.rpe(halves: EditAdv.referenceRPEHalves(hundredths: hundredths))
            tally.check(value == expected, "\(hundredths)/100 gave \(value), expected \(expected)")
            tally.check(RPE(value) != nil, "\(hundredths)/100 gave \(value), which RPE(_:) refuses")
        }
        #expect(tally.passed, tally.summary)
    }

    @Test("RestDuration(clampingSeconds:) is RestDuration(seconds:) for each of the nineteen valid values.")
    func restClamping_validValues_agreeWithTheFailableInitializer() {
        for seconds in stride(from: 30, through: 300, by: 15) {
            #expect(RestDuration(clampingSeconds: seconds) == RestDuration(seconds: seconds), "\(seconds) s")
        }
        #expect(RestDuration.stepSeconds == 15)
        #expect(RestDuration(clampingSeconds: 90) == .defaultRest)
    }

    @Test("RestDuration(clampingSeconds:) of every second from −1,000 to 1,000 is the nearest 15 in 30…300.")
    func restClamping_everySecond_isTheNearestFifteenInRange() {
        var tally = Tally()
        for seconds in -1000 ... 1000 {
            let rest = RestDuration(clampingSeconds: seconds).seconds
            tally.check(rest == EditAdv.referenceRest(seconds), "\(seconds) s gave \(rest)")
            tally.check(RestDuration(seconds: rest) != nil, "\(seconds) s gave \(rest), which the model refuses")
        }
        #expect(tally.passed, tally.summary)
        #expect([37, 38].map { RestDuration(clampingSeconds: $0).seconds } == [30, 45])
    }

    @Test("A value far from a half by less than a float can tell still goes to its nearer half: no Double on the way.")
    func rpeClamping_valuesAFloatCannotTell_areExact() {
        #expect(RPE(clamping: dec("7.249999999999999999999999")).value == 7)
        #expect(RPE(clamping: dec("7.250000000000000000000001")).value == dec("7.5"))
        #expect(RPE(clamping: dec("9.749999999999999999999999")).value == dec("9.5"))
        #expect(RPE(clamping: dec("4.999999999999999999999999")).value == 5)
        #expect(RPE(clamping: dec("10.00000000000000000000001")).value == 10)
        #expect(RPE(clamping: dec("7.2499999999999999999999999999999999999")).value == 7)
        #expect(RPE(clamping: dec("7.7500000000000000000000000000000000001")).value == 8)
        #expect(RPE(clamping: Decimal(22) / 3).value == dec("7.5"), "7.33… with a 38-digit mantissa")
        #expect(RPE(clamping: Decimal(20) / 3).value == dec("6.5"), "6.66… with a 38-digit mantissa")
        #expect(RPE(clamping: Decimal(29) / 3).value == dec("9.5"), "9.66… with a 38-digit mantissa")
    }
}
