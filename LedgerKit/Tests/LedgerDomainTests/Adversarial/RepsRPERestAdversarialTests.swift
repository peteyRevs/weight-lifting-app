import Foundation
@testable import LedgerDomain
import Testing

@Suite("Reps, RPE and RestDuration (adversarial)", .tags(.domain))
struct RepsRPERestAdversarialTests {
    /// Every legal rest (rule 3: 30…300 in 15 s steps) with its rule 39 label:
    /// "{s}s" under 60 s, "{m} min" on whole minutes, "m:ss" otherwise.
    static let restLabels: [(Int, String)] = [
        (30, "30s"), (45, "45s"), (60, "1 min"), (75, "1:15"), (90, "1:30"), (105, "1:45"),
        (120, "2 min"), (135, "2:15"), (150, "2:30"), (165, "2:45"), (180, "3 min"), (195, "3:15"),
        (210, "3:30"), (225, "3:45"), (240, "4 min"), (255, "4:15"), (270, "4:30"), (285, "4:45"),
        (300, "5 min")
    ]
}

extension RepsRPERestAdversarialTests {
    @Test("Reps rejects anything below 1 and clamping lifts it to 1 (rule 2).", arguments: [0, -1, Int.min])
    func reps_belowOne_isNilAndClampsToOne(value: Int) {
        #expect(Reps(value) == nil)
        #expect(Reps(clamping: value) == .one)
    }

    @Test("Reps accepts 1 and large counts unchanged.", arguments: [1, 2, 12, 13, 100, Int.max])
    func reps_positive_isAccepted(value: Int) {
        #expect(Reps(value)?.value == value)
        #expect(Reps(clamping: value).value == value)
    }

    @Test("Reps orders by count and decodes only valid counts.")
    func reps_orderingAndDecoding() throws {
        #expect(try Fixtures.reps(4) < Fixtures.reps(5))
        #expect(try JSONDecoder().decode(Reps.self, from: Data("5".utf8)).value == 5)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Reps.self, from: Data("0".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Reps.self, from: Data("-3".utf8)) }
    }

    @Test(
        "RPE accepts exactly 5…10 in half points (rule 3).",
        arguments: ["5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "8.0", "8.50"]
    )
    func rpe_legalValues_areAccepted(text: String) {
        #expect(RPE(dec(text))?.value == dec(text))
    }

    @Test(
        "RPE rejects values off the half-point grid or outside 5…10 (criterion 13's 4.75).",
        arguments: ["4.75", "4.5", "4.99", "10.5", "10.01", "7.25", "7.3", "0", "-8", "11", "7.49999", "NaN"]
    )
    func rpe_illegalValues_areNil(text: String) {
        #expect(RPE(dec(text)) == nil)
    }

    @Test("RPE 8 and 8.0 are the same value with the same hash and label.")
    func rpe_equivalentDecimals_areEqual() throws {
        let plain = try Fixtures.rpe(8)
        let padded = try Fixtures.rpe(dec("8.0"))
        #expect(plain == padded)
        #expect(Set([plain, padded]).count == 1)
        #expect(plain.label == "8")
        #expect(try Fixtures.rpe(dec("8.5")).label == "8.5")
        #expect(try Fixtures.rpe(dec("9.5")) > Fixtures.rpe(9))
    }

    @Test("RPE decoding re-validates the number.")
    func rpe_decoding_revalidates() throws {
        #expect(try JSONDecoder().decode(RPE.self, from: Data("8.5".utf8)) == Fixtures.rpe(dec("8.5")))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RPE.self, from: Data("4.75".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RPE.self, from: Data("7.25".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RPE.self, from: Data("10.5".utf8)) }
    }

    @Test("Every legal rest has the rule 39 label.", arguments: restLabels)
    func restLabel_everyLegalValue(seconds: Int, label: String) throws {
        #expect(try Fixtures.rest(seconds).label == label)
    }

    @Test(
        "RestDuration rejects values off the 15 s grid or outside 30…300 (criterion 13's 100).",
        arguments: [100, 0, -15, 15, 29, 31, 44, 301, 315, 600, 91]
    )
    func rest_illegalValues_areNil(seconds: Int) {
        #expect(RestDuration(seconds: seconds) == nil)
    }

    @Test("RestDuration exposes its Duration, orders by seconds and re-validates on decode.")
    func rest_durationOrderingDecoding() throws {
        #expect(try Fixtures.rest(90).duration == .seconds(90))
        #expect(RestDuration.defaultRest.seconds == 90)
        #expect(try Fixtures.rest(60) < Fixtures.rest(75))
        #expect(try JSONDecoder().decode(RestDuration.self, from: Data("150".utf8)).seconds == 150)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RestDuration.self, from: Data("100".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RestDuration.self, from: Data("315".utf8)) }
    }
}

@Suite("Volume (adversarial)", .tags(.domain))
struct VolumeAdversarialTests {}

extension VolumeAdversarialTests {
    @Test("Volume of one set is weight × reps in gram·reps (rule 34).")
    func volume_ofSet_isGramsTimesReps() throws {
        // ADR-007: exact, 185 lb = 83,914.58845 g.
        #expect(try Volume(weight: pounds("185"), reps: Fixtures.reps(5)).gramReps == dec("83914.58845") * 5)
        #expect(try Volume(weight: .zero, reps: Fixtures.reps(12)) == .zero)
        #expect(try Volume(weight: kilos("100"), reps: Fixtures.reps(3)).gramReps == 300_000)
    }

    @Test("Volume formats whole units with thousands separators (rule 34).")
    func volume_formatted_thousandsSeparators() throws {
        // 24,180 lb = 10,967,863.5066 g exactly (ADR-007) → "24,180".
        #expect(try Volume(weight: pounds("24180"), reps: Fixtures.reps(1)).formatted(in: .lb) == "24,180")
        #expect(Volume.zero.formatted(in: .lb) == "0")
        #expect(Volume(gramReps: 999_000).formatted(in: .kg) == "999")
        #expect(Volume(gramReps: 1_000_000).formatted(in: .kg) == "1,000")
        #expect(Volume(gramReps: 1_234_567_000).formatted(in: .kg) == "1,234,567")
    }

    @Test("A realistic week of pound sets totals the exact pound volume (rule 34, user story 2).")
    func volume_realisticWeek_hasNoVisibleDrift() throws {
        // 16 sessions × 5 × 5 @ 185 lb = 400 reps → 74,000 lb exactly.
        let set = try Volume(weight: pounds("185"), reps: Fixtures.reps(5))
        let week = (0 ..< 80).reduce(Volume.zero) { total, _ in total + set }
        #expect(week.formatted(in: .lb) == "74,000")
    }

    @Test("compact(in:) is thousands to exactly one decimal plus k (rule 34).")
    func volume_compact_oneDecimalK() {
        #expect(Volume(gramReps: 41_200_000).compact(in: .kg) == "41.2k")
        #expect(Volume(gramReps: 24_000_000).compact(in: .kg) == "24.0k")
        #expect(Volume(gramReps: 500_000).compact(in: .kg) == "0.5k")
        #expect(Volume.zero.compact(in: .lb) == "0.0k")
        // 18,687,966 g = 41,200.0008 lb → 41.2k lb.
        #expect(Volume(gramReps: 18_687_966).compact(in: .lb) == "41.2k")
    }

    @Test("Volume adds, subtracts and orders by gram·reps.")
    func volume_arithmetic() {
        let small = Volume(gramReps: 10)
        let large = Volume(gramReps: 25)
        #expect((small + large).gramReps == 35)
        #expect((large - small).gramReps == 15)
        #expect(small < large)
        #expect(small + .zero == small)
    }
}

@Suite("Equipment and Weekday (adversarial)", .tags(.domain))
struct EquipmentWeekdayAdversarialTests {}

extension EquipmentWeekdayAdversarialTests {
    @Test(
        "Default steps: lb barbell 5 else 2.5; kg barbell 2.5 else 1.25 (rule 1, decision #9).",
        arguments: Equipment.allCases
    )
    func defaultStep_perEquipmentAndUnit(equipment: Equipment) {
        #expect(equipment.defaultStep(in: .lb) == (equipment == .barbell ? pounds("5") : pounds("2.5")))
        #expect(equipment.defaultStep(in: .kg) == (equipment == .barbell ? kilos("2.5") : kilos("1.25")))
    }

    @Test("Weekday maps Foundation's Sunday-first numbering both ways.")
    func weekday_calendarWeekdayMapping() {
        #expect(Weekday(calendarWeekday: 1) == .sunday)
        #expect(Weekday(calendarWeekday: 2) == .monday)
        #expect(Weekday(calendarWeekday: 7) == .saturday)
        #expect(Weekday(calendarWeekday: 0) == nil)
        #expect(Weekday(calendarWeekday: 8) == nil)
        for day in Weekday.allCases {
            #expect(Weekday(calendarWeekday: day.calendarWeekday) == day)
        }
        #expect(Weekday.monday.rawValue == 1)
        #expect(Weekday.sunday.rawValue == 7)
    }

    @Test("The default week start follows the calendar's first weekday (decision #15).")
    func weekday_firstOfCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        #expect(Weekday.first(of: calendar) == .sunday)
        calendar.firstWeekday = 2
        #expect(Weekday.first(of: calendar) == .monday)
        calendar.firstWeekday = 7
        #expect(Weekday.first(of: calendar) == .saturday)
    }
}
