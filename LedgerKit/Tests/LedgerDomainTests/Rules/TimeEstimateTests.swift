import Foundation
@testable import LedgerDomain
import Testing

@Suite("TimeEstimate", .tags(.domain))
struct TimeEstimateTests {
    private func day(_ slots: [Slot]) -> DayTemplate {
        DayTemplate(id: DayTemplateID(Fixtures.uuid(1)), name: "Day", tag: "D1", slots: slots)
    }

    @Test("Straight slots cost (42 s + rest) per set, rounded to whole minutes (decision #14, criterion 9)")
    func minutes_solo_isSumOf42PlusRestPerSet() throws {
        let slots = try [
            Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 5, rest: 150),
            Fixtures.slot(Fixtures.inclineDB, id: 2, sets: 3, reps: 10, rest: 90),
            Fixtures.slot(Fixtures.chestSupportedRow, id: 3, sets: 4, reps: 8, rest: 90),
            Fixtures.slot(Fixtures.latPulldown, id: 4, sets: 3, reps: 12, rest: 75),
            Fixtures.slot(Fixtures.lateralRaise, id: 5, sets: 3, reps: 15, rest: 60)
        ]
        // 5×(42+150) + 3×(42+90) + 4×(42+90) + 3×(42+75) + 3×(42+60)
        // = 960 + 396 + 528 + 351 + 306 = 2541 s = 42.35 min → 42.
        #expect(TimeEstimate.minutes(day: day(slots), prescriptions: [:]) == 42)
    }

    @Test("A superset rests once per round, for its longest member rest (decision #14, criterion 9)")
    func minutes_superset_countsRestOncePerRound() throws {
        let slots = try [
            Fixtures.slot(Fixtures.latPulldown, id: 1, sets: 3, reps: 12, rest: 90),
            Fixtures.slot(Fixtures.lateralRaise, id: 2, sets: 3, reps: 15, rest: 60, superset: true)
        ]
        // Work 6 × 42 = 252 s plus 3 rests of 90 s = 270 s → 522 s = 8.7 min → 9.
        #expect(TimeEstimate.minutes(day: day(slots), prescriptions: [:]) == 9)
        // The same two slots straight: 3×(42+90) + 3×(42+60) = 702 s = 11.7 → 12.
        let straight = try [slots[0], Fixtures.slot(Fixtures.lateralRaise, id: 2, sets: 3, reps: 15, rest: 60)]
        #expect(TimeEstimate.minutes(day: day(straight), prescriptions: [:]) == 12)
    }

    @Test("A drop set counts as one more set and one more round (decision #14)")
    func minutes_dropSetCounted() throws {
        let curl = try Fixtures.slot(Fixtures.barbellCurl, id: 1, sets: 3, reps: 12, rest: 60, dropSets: 1)
        // (3 + 1) × (42 + 60) = 408 s = 6.8 min → 7.
        #expect(TimeEstimate.minutes(day: day([curl]), prescriptions: [:]) == 7)
    }

    @Test("The spec's Upper A day is 39 minutes by the formula")
    func minutes_upperA_seedDay() throws {
        // 960 + 396 + 528 + (6 × 42 + 3 × 75 = 477) = 2361 s = 39.35 min → 39.
        #expect(try TimeEstimate.minutes(day: Fixtures.upperA(), prescriptions: [:]) == 39)
    }

    @Test("Prescribed sets and rest override the slot's (deload weeks are shorter)")
    func minutes_usesPrescriptions() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 1, sets: 5, reps: 5, rest: 180)
        let deload = ProgressionRules.prescribe(
            week: Fixtures.week(7, deload: true), weekIndex: 7, slot: slot, exercise: Fixtures.backSquat, units: .lb
        )
        // 5 × 222 = 1110 s → 18.5 → 19; deload 4 × 222 = 888 s → 14.8 → 15.
        #expect(TimeEstimate.minutes(day: day([slot]), prescriptions: [:]) == 19)
        #expect(TimeEstimate.minutes(day: day([slot]), prescriptions: [slot.id: deload]) == 15)
    }

    @Test("An empty day is zero minutes; totals round to the nearest minute")
    func minutes_emptyAndRounding() throws {
        #expect(TimeEstimate.minutes(day: day([]), prescriptions: [:]) == 0)
        // 1 × (42 + 45) = 87 s = 1.45 min → 1.
        let short = try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 5, rest: 45)
        #expect(TimeEstimate.minutes(day: day([short]), prescriptions: [:]) == 1)
        // 5 × (42 + 30) = 360 s = 6 min exactly. (A half minute, 18.5, rounds up: see the deload test.)
        let fiveShort = try Fixtures.slot(Fixtures.bench, id: 2, sets: 5, reps: 5, rest: 30)
        #expect(TimeEstimate.minutes(day: day([fiveShort]), prescriptions: [:]) == 6)
    }
}
