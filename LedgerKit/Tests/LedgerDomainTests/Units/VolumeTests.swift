import Foundation
@testable import LedgerDomain
import Testing

@Suite("Volume", .tags(.domain))
struct VolumeTests {
    @Test("A set's volume is weight × reps in gram·reps (rule 34)")
    func init_weightTimesReps() throws {
        let volume = try Volume(weight: .pounds(185), reps: Fixtures.reps(5))
        #expect(volume.gramReps == dec("83914.58845") * 5)
        #expect(volume.formatted(in: .lb) == "925")
    }

    @Test("Formatted volume is whole units with thousands separators (rule 34)")
    func formatted_thousandsSeparators() {
        let volume = Volume(gramReps: Weight.pounds(24180).grams)
        #expect(volume.formatted(in: .lb) == "24,180")
        #expect(Volume(gramReps: 1_000_000_000).formatted(in: .kg) == "1,000,000")
        #expect(Volume.zero.formatted(in: .lb) == "0")
        #expect(Volume(gramReps: -Weight.pounds(1500).grams).formatted(in: .lb) == "-1,500")
    }

    @Test("Compact volume is thousands to one decimal plus k (rule 34)")
    func compact_oneDecimalK() {
        #expect(Volume(gramReps: Weight.pounds(24180).grams).compact(in: .lb) == "24.2k")
        #expect(Volume(gramReps: Weight.pounds(41200).grams).compact(in: .lb) == "41.2k")
        #expect(Volume(gramReps: Weight.pounds(24000).grams).compact(in: .lb) == "24.0k")
        #expect(Volume(gramReps: Weight.pounds(460).grams).compact(in: .lb) == "0.5k")
        #expect(Volume(gramReps: 1_234_500_000).compact(in: .kg) == "1,234.5k")
    }

    @Test("Volume is exact at any horizon: 1,000 reps of 185 lb is 185,000 lb moved (ADR-007)")
    func sum_isExact_noDrift() throws {
        let set = try Volume(weight: .pounds(185), reps: Fixtures.reps(1))
        let lifetime = (0 ..< 1000).reduce(Volume.zero) { total, _ in total + set }
        #expect(lifetime.formatted(in: .lb) == "185,000")
        #expect(lifetime == Volume(weight: .pounds(185_000), reps: .one))
    }

    @Test("Volumes add, subtract and order by gram·reps")
    func arithmetic_andOrder() {
        let small = Volume(gramReps: 100)
        let large = Volume(gramReps: 350)
        #expect(small + large == Volume(gramReps: 450))
        #expect(large - small == Volume(gramReps: 250))
        #expect(small < large)
        #expect([small, large].reduce(.zero, +) == Volume(gramReps: 450))
    }

    @Test("Volume encodes as gram·reps and decodes back")
    func codable_roundTrip_preservesValue() throws {
        let volume = Volume(gramReps: 419_575)
        let data = try JSONEncoder().encode(volume)
        #expect(try Fixtures.json(volume) == #"{"gramReps":"419575"}"#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Volume.self, from: Data(#"{"gramReps":419575}"#.utf8))
        }
        #expect(try JSONDecoder().decode(Volume.self, from: data) == volume)
    }
}

// MARK: - Percent change (F09 S2, criterion 2)

extension VolumeTests {
    /// `text` pounds lifted once, as a volume.
    static func lb(_ text: String) -> Volume {
        Volume(gramReps: Weight.pounds(dec(text)).grams)
    }

    /// `text` kilograms lifted once, as a volume.
    static func kg(_ text: String) -> Volume {
        Volume(gramReps: Weight.kilograms(dec(text)).grams)
    }

    @Test("The change from the previous volume is a whole percent, whatever the unit (rule 43)")
    func percentChange_isAWholePercent() {
        #expect(Self.lb("24180").percentChange(from: Self.lb("22400")) == 8)
        #expect(Self.lb("21728").percentChange(from: Self.lb("22400")) == -3)
        #expect(Self.lb("22400").percentChange(from: Self.lb("22400")) == 0)
        #expect(Self.lb("44800").percentChange(from: Self.lb("22400")) == 100)
        #expect(Volume.zero.percentChange(from: Self.lb("22400")) == -100)
        // 10,968 kg after 10,160 kg is +7.95 %; 1,000 kg after 2,000 lb (907.18474 kg) is +10.23 %.
        #expect(Self.kg("10968").percentChange(from: Self.kg("10160")) == 8)
        #expect(Self.kg("1000").percentChange(from: Self.lb("2000")) == 10)
    }

    @Test(
        "The percent is rounded once, half away from zero, for falls as for rises",
        arguments: [
            ("201", "200", 1), ("199", "200", -1), ("203", "200", 2), ("197", "200", -2),
            ("22960", "22400", 3), ("21840", "22400", -3), ("22957.76", "22400", 2), ("21842.24", "22400", -2),
            ("200.98", "200", 0), ("199.02", "200", 0), ("201.02", "200", 1), ("198.98", "200", -1),
            ("1.995", "1", 100), ("0.005", "1", -100), ("1.994", "1", 99), ("0.006", "1", -99)
        ]
    )
    func percentChange_ties_roundAwayFromZero(current: String, previous: String, percent: Int) {
        #expect(Self.lb(current).percentChange(from: Self.lb(previous)) == percent)
        #expect(Self.kg(current).percentChange(from: Self.kg(previous)) == percent)
    }

    @Test("With a zero previous volume there is no percentage")
    func percentChange_zeroPrevious_isNil() {
        let noReps = Volume(gramReps: Decimal(sign: .plus, exponent: 3, significand: 0))
        for previous in [Volume.zero, noReps, Self.lb("185") - Self.lb("185")] {
            #expect(Self.lb("24180").percentChange(from: previous) == nil)
            #expect(Volume.zero.percentChange(from: previous) == nil)
            #expect((Volume.zero - Self.lb("100")).percentChange(from: previous) == nil)
            #expect(Volume(gramReps: .nan).percentChange(from: previous) == nil)
        }
    }

    @Test("A negative previous volume follows the formula as written: (this − previous) ÷ previous")
    func percentChange_negativePrevious_followsTheFormula() {
        #expect(Volume(gramReps: -50).percentChange(from: Volume(gramReps: -100)) == -50)
        #expect(Volume(gramReps: 100).percentChange(from: Volume(gramReps: -100)) == -200)
        #expect(Volume(gramReps: -100).percentChange(from: Volume(gramReps: 100)) == -200)
    }

    @Test("A change too large for Int is clamped to Int.min or Int.max")
    func percentChange_beyondInt_isClamped() {
        // After a previous volume of 100, the change in percent is the current volume minus 100.
        let hundred = Volume(gramReps: 100)
        #expect(Volume(gramReps: Decimal(Int.max) + 99).percentChange(from: hundred) == Int.max - 1)
        #expect(Volume(gramReps: Decimal(Int.max) + 100).percentChange(from: hundred) == Int.max)
        #expect(Volume(gramReps: Decimal(Int.max) + 101).percentChange(from: hundred) == Int.max)
        #expect(Volume(gramReps: Decimal(Int.min) + 101).percentChange(from: hundred) == Int.min + 1)
        #expect(Volume(gramReps: Decimal(Int.min) + 100).percentChange(from: hundred) == Int.min)
        #expect(Volume(gramReps: Decimal(Int.min) + 99).percentChange(from: hundred) == Int.min)
        let huge = Volume(gramReps: Decimal(sign: .plus, exponent: 60, significand: 1))
        #expect(huge.percentChange(from: hundred) == Int.max)
        #expect((Volume.zero - huge).percentChange(from: hundred) == Int.min)
        #expect(hundred.percentChange(from: huge) == -100)
        #expect(Volume(gramReps: .greatestFiniteMagnitude).percentChange(from: hundred) == Int.max)
    }

    @Test("A change that is not a number is nil: a NaN volume, or arithmetic past Decimal's own range")
    func percentChange_notANumber_isNil() {
        let hundred = Volume(gramReps: 100)
        let notANumber = Volume(gramReps: .nan)
        #expect(notANumber.percentChange(from: hundred) == nil)
        #expect(hundred.percentChange(from: notANumber) == nil)
        #expect(notANumber.percentChange(from: notANumber) == nil)
        let greatest = Volume(gramReps: .greatestFiniteMagnitude)
        let least = Volume(gramReps: .leastNonzeroMagnitude)
        // The quotient, then the difference, leaves Decimal's range (about 3.4 × 10^165).
        #expect(greatest.percentChange(from: least) == nil)
        #expect(greatest.percentChange(from: Volume.zero - greatest) == nil)
        // Inside it the extremes still compute.
        #expect(greatest.percentChange(from: greatest) == 0)
        #expect(least.percentChange(from: greatest) == -100)
        #expect(least.percentChange(from: least) == 0)
    }
}

// MARK: - The tile's number (F09 S2, criterion 3)

extension VolumeTests {
    @Test("The tile's number is what compact prints, without the k, in pounds and in kilograms (rule 34)")
    func thousands_isCompactWithoutTheK() {
        #expect(Self.lb("24180").thousands(in: .lb) == "24.2")
        #expect(Self.lb("41200").thousands(in: .lb) == "41.2")
        #expect(Self.lb("24000").thousands(in: .lb) == "24.0")
        #expect(Self.lb("460").thousands(in: .lb) == "0.5")
        #expect(Volume(gramReps: 1_234_500_000).thousands(in: .kg) == "1,234.5")
        // 24,180 lb is 10,967.86 kg; 24,180 kg is 53,307.8 lb.
        #expect(Self.lb("24180").thousands(in: .kg) == "11.0")
        #expect(Self.kg("24180").thousands(in: .kg) == "24.2")
        #expect(Self.kg("24180").thousands(in: .lb) == "53.3")
        #expect((Volume.zero - Self.lb("24180")).thousands(in: .lb) == "-24.2")
    }

    @Test("Zero reads 0; every other volume keeps one decimal, as compact does (F09 criterion 8)")
    func thousands_zero_readsZero() {
        let noReps = Volume(gramReps: Decimal(sign: .plus, exponent: 3, significand: 0))
        for zero in [Volume.zero, noReps, Self.lb("185") - Self.lb("185")] {
            #expect(zero.thousands(in: .lb) == "0")
            #expect(zero.thousands(in: .kg) == "0")
        }
        #expect(Volume.zero.compact(in: .lb) == "0.0k")
        #expect(Self.lb("40").thousands(in: .lb) == "0.0")
        #expect(Self.lb("49.99").thousands(in: .lb) == "0.0")
        #expect(Self.lb("50").thousands(in: .lb) == "0.1")
        #expect(Self.kg("0.001").thousands(in: .kg) == "0.0")
        #expect((Volume.zero - Self.lb("40")).thousands(in: .lb) == "0.0")
    }

    @Test(
        "The tile's number plus k is compact's text, digit for digit",
        arguments: ["0.01", "49.99", "50", "999.99", "24180", "99949.99", "99950", "1234567.89", "-24180", "-0.5"]
    )
    func thousands_plusK_isCompact(amount: String) {
        for volume in [Self.lb(amount), Self.kg(amount)] {
            for units in Units.allCases {
                #expect(volume.thousands(in: units) + "k" == volume.compact(in: units), "\(amount) in \(units)")
            }
        }
    }

    @Test("Volumes no lifter moves print without trapping, and never with a k")
    func thousands_extremes_neverTrap() {
        let extremes: [Decimal] = [.greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude, .nan]
        for gramReps in extremes {
            for units in Units.allCases {
                let text = Volume(gramReps: gramReps).thousands(in: units)
                #expect(!text.isEmpty && !text.hasSuffix("k"), "\(gramReps) in \(units)")
            }
        }
    }
}
