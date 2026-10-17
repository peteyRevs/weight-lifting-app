import Foundation
@testable import LedgerDomain
import Testing

/// The rulings after round 1 (the brief's criteria 14 and 16, and the limits the fixes now name once):
/// choosing the progression a slot already has changes nothing, and each named limit is the limit its
/// initializer enforced before. Expected values are the rules' numbers, written out here.
@Suite("Editing after round 1 (adversarial)", .tags(.domain))
struct EditingRoundTwoAdversarialTests {
    static let slot = EditAdv.slotID(5001)

    /// Three slots, the middle one with these numbers, joined to the first.
    static func day(reps: Int, top: Int, _ progression: Progression) throws -> DayTemplate {
        var day = try EditAdv.day(flags: [false, true, false])
        day.slots[1] = try Fixtures.slot(
            Fixtures.bench, id: 5001, reps: reps, repsHi: top, progression: progression, superset: true, misses: [2]
        )
        return day
    }

    static func top(_ day: DayTemplate) -> Int {
        day.slots[1].repsHi
    }
}

extension EditingRoundTwoAdversarialTests {
    @Test("Criterion 14: the progression a slot already has, chosen again, returns the very same day, from every pair.")
    func setProgression_sameProgression_returnsTheSameDay() throws {
        var tally = Tally()
        for pair in DayEditingFieldsAdversarialTests.pairs {
            for progression in Progression.allCases {
                let day = try Self.day(reps: pair.reps, top: pair.top, progression)
                let again = DayEditing.setProgression(progression, slot: Self.slot, in: day)
                tally.check(again == day, "reps \(pair.reps), top \(pair.top), \(progression): top \(Self.top(again))")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 735 * 3)
    }

    @Test("Criterion 14: a range narrowed after Double stays narrow under a second and a third Double.")
    func setProgression_doubleAgain_neverWidensANarrowedRange() throws {
        var tally = Tally()
        for reps in 1 ... 30 {
            for start in [Progression.linear, .fixed] {
                let doubled = try DayEditing.setProgression(
                    .double,
                    slot: Self.slot,
                    in: Self.day(reps: reps, top: reps + 1, start)
                )
                tally.check(Self.top(doubled) == reps + 2, "reps \(reps) from \(start): top \(Self.top(doubled))")
                let narrowed = DayEditing.set(.repsHi(reps + 1), slot: Self.slot, in: doubled)
                tally.check(Self.top(narrowed) == reps + 1, "reps \(reps): narrowed to \(Self.top(narrowed))")
                let twice = DayEditing.setProgression(.double, slot: Self.slot, in: narrowed)
                let thrice = DayEditing.setProgression(.double, slot: Self.slot, in: twice)
                tally.check(twice == narrowed && thrice == narrowed, "reps \(reps): top \(Self.top(thrice))")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 30 * 2 * 3)
    }

    @Test(
        "Criterion 14: to Double, away and back, from every pair: the top is max(top, reps + 2) each time, never more."
    )
    func setProgression_toDoubleAwayAndBack_raisesTheTopOnce() throws {
        var tally = Tally()
        for pair in DayEditingFieldsAdversarialTests.pairs {
            for other in [Progression.linear, .fixed] {
                var day = try Self.day(reps: pair.reps, top: pair.top, other)
                let original = day.slots[1]
                let expected = max(pair.top, pair.reps + 2)
                var tops: [Int] = []
                for target in [Progression.double, other, .double, .double, other] {
                    day = DayEditing.setProgression(target, slot: Self.slot, in: day)
                    tops.append(Self.top(day))
                }
                var last = original
                last.repsHi = expected
                let holds = tops == Array(repeating: expected, count: 5) && day.slots[1] == last
                tally.check(holds, "reps \(pair.reps), top \(pair.top), \(other): tops \(tops)")
                tally.check(EditAdv.rejection(of: day.slots) == nil, "reps \(pair.reps), top \(pair.top): refused")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 735 * 2 * 2)
    }

    @Test(
        "Criterion 14: reps raised under Double still push the top, and choosing Double again leaves what they pushed."
    )
    func setProgression_afterRepsPushTheTop_keepsIt() throws {
        let day = try Self.day(reps: 8, top: 10, .double)
        let pushed = DayEditing.set(.reps(10), slot: Self.slot, in: day)
        let numbers = [pushed.slots[1].reps, Self.top(pushed)]
        #expect(numbers == [10, 11])
        let again = DayEditing.setProgression(.double, slot: Self.slot, in: pushed) == pushed
        #expect(again, "a second Double widened 10–11 to 10–12")
    }
}

// MARK: - The limits named once

extension EditingRoundTwoAdversarialTests {
    @Test("RPE's named range and step are 5…10 and a half, and RPE(_:) accepts exactly the eleven halves in it.")
    func rpe_namedRange_isWhatTheInitializerAccepts() {
        #expect(RPE.range == 5 ... 10)
        #expect(RPE.step == dec("0.5"))
        var tally = Tally()
        for hundredths in -500 ... 1500 {
            let valid = (500 ... 1000).contains(hundredths) && hundredths.isMultiple(of: 50)
            tally.check((RPE(EditAdv.decimal(hundredths: hundredths)) != nil) == valid, "\(hundredths)/100")
        }
        #expect(tally.passed, tally.summary)
        #expect(RPE(.nan) == nil)
        #expect(RPE(dec("5.0000000000000000000000001")) == nil)
        #expect(RPE(dec("10.5")) == nil && RPE(dec("4.5")) == nil)
    }

    @Test("A deload still lowers each of the eleven RPE values by 2 and never below 5 (rule 12).")
    func rpe_deloaded_isTwoLowerAndNeverBelowFive() {
        for halves in 10 ... 20 {
            let deloaded = RPE(clamping: EditAdv.rpe(halves: halves)).deloaded().value
            #expect(deloaded == EditAdv.rpe(halves: max(10, halves - 4)), "RPE \(EditAdv.rpe(halves: halves))")
        }
    }

    @Test("Rest's named range and step are 30…300 s and 15 s, and RestDuration(seconds:) accepts exactly the nineteen.")
    func rest_namedRange_isWhatTheInitializerAccepts() {
        #expect(RestDuration.secondsRange == 30 ... 300)
        #expect(RestDuration.stepSeconds == 15)
        var tally = Tally()
        var accepted = 0
        for seconds in -1000 ... 1000 {
            let valid = (30 ... 300).contains(seconds) && seconds.isMultiple(of: 15)
            let isAccepted = RestDuration(seconds: seconds) != nil
            accepted += isAccepted ? 1 : 0
            tally.check(isAccepted == valid, "\(seconds) s")
        }
        #expect(tally.passed, tally.summary)
        #expect(accepted == 19)
        #expect(RestDuration(seconds: .min) == nil && RestDuration(seconds: .max) == nil)
    }

    @Test("The named minimum is two weeks: Program.init refuses none and one, and \"−\" refuses two and takes three.")
    func program_namedMinimum_isTwoWeeks() throws {
        #expect(Program.minimumWeeks == 2)
        for count in 0 ... 1 {
            #expect(throws: ProgramValidationError.tooFewWeeks(count: count)) {
                try EditAdv.program(weeks: EditAdv.restWeeks(count), days: [])
            }
        }
        let two = try EditAdv.program(weeks: EditAdv.restWeeks(2), days: [])
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(two, loggedWeeks: [])
        }
        let three = try EditAdv.program(weeks: EditAdv.restWeeks(3), days: [])
        #expect(try ProgramEditing.removeLastWeek(three, loggedWeeks: []).weeks.count == 2)
    }
}
