import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// The column encodings that replace GRDB's defaults (F05 implementation notes, "Weight encoding" and
/// "Date encoding"): exact `_e7g` weights (ADR-007), `REAL` dates, text UUIDs and bit-pattern seqs.
@Suite("ColumnCodec", .tags(.persistence))
struct ColumnCodecTests {
    // MARK: Weights (ADR-007)

    @Test("A weight is stored as an exact count of 10⁻⁷ g: 0.01 lb is 45,359,237 and 185 lb 839,145,884,500")
    func e7g_examples() throws {
        #expect(try Weight.pounds(Decimal(1) / 100).e7g() == 45_359_237)
        #expect(try Weight.pounds(185).e7g() == 839_145_884_500)
        #expect(try Weight.pounds(-2.5).e7g() == -11_339_809_250)
        #expect(try Weight.kilograms(20).e7g() == 200_000_000_000)
        #expect(try Weight(grams: 1).e7g() == 10_000_000)
        #expect(try Weight(grams: Self.units(1)).e7g() == 1)
        #expect(try Weight.zero.e7g() == 0)
        #expect(try Volume(weight: .pounds(185), reps: Reps(clamping: 5)).e7gReps() == 4_195_729_422_500)
    }

    @Test("The storage boundary refuses a weight it cannot keep exactly, rather than round it")
    func e7g_refusesInexactWeights() throws {
        let eighth = Weight.pounds(Decimal(1) / 8) // 56.69904625 g: 566,990,462.5 units
        #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) { try eighth.e7g() }
        let tenthOfAUnit = Weight(grams: Decimal(sign: .plus, exponent: -8, significand: 1))
        #expect(throws: LedgerPersistenceError.inexactWeight(tenthOfAUnit.grams)) { try tenthOfAUnit.e7g() }
        // Int64's edge is ±922,337,203,685.4775807 g, about 922 kilotonnes.
        let largest = Weight(grams: Self.units(Decimal(Int64.max)))
        #expect(try largest.e7g() == .max)
        let beyond = largest + Weight(grams: Self.units(1))
        #expect(throws: LedgerPersistenceError.inexactWeight(beyond.grams)) { try beyond.e7g() }
        #expect(try Weight(e7g: .min).e7g() == .min)
        // Beyond Decimal's exponent range once shifted by 7, and NaN: no exact count either.
        let immense = Weight(grams: Decimal(sign: .plus, exponent: 125, significand: 1))
        #expect(throws: LedgerPersistenceError.inexactWeight(immense.grams)) { try immense.e7g() }
        #expect(throws: LedgerPersistenceError.self) { try Weight(grams: .nan).e7g() }
        let volume = Volume(gramReps: beyond.grams)
        #expect(throws: LedgerPersistenceError.inexactWeight(volume.gramReps)) { try volume.e7gReps() }
    }

    @Test(
        "Every count reads back as itself, and every storable weight and volume round-trips exactly",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func e7g_roundTrips(_ seed: PropertySeed) throws {
        var random = seed.generator
        let count = Int64.random(in: .min ... .max, using: &random)
        #expect(try Weight(e7g: count).e7g() == count)
        #expect(try Volume(e7gReps: count).e7gReps() == count)
        // A lifter's weights: hundredths of a pound, grams, and any whole count at any scale.
        let pounds = Weight.pounds(Decimal(Int.random(in: -100_000_000 ... 100_000_000, using: &random)) / 100)
        let kilograms = Weight
            .kilograms(Decimal(Int.random(in: -1_000_000_000 ... 1_000_000_000, using: &random)) / 1000)
        let exponent = Int.random(in: -7 ... 2, using: &random) // at most 10¹¹ g, inside Int64 once shifted
        let scaled = Weight(grams: Decimal(
            sign: .plus,
            exponent: exponent,
            significand: Decimal(Int64.random(in: -999_999_999 ... 999_999_999, using: &random))
        ))
        for weight in [pounds, kilograms, scaled] {
            #expect(try Weight(e7g: weight.e7g()) == weight, "\(weight.grams) g")
        }
        let volume = Volume(weight: pounds, reps: Reps(clamping: Int.random(in: 1 ... 100, using: &random)))
        #expect(try Volume(e7gReps: volume.e7gReps()) == volume)
    }

    // MARK: Dates

    @Test(
        "A date column keeps seconds since 2001 to the last bit through SQLite's REAL",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func seconds_roundTripThroughREAL(_ seed: PropertySeed) throws {
        var random = seed.generator
        var anyFinite = Double(bitPattern: random.next())
        while !anyFinite.isFinite {
            anyFinite = Double(bitPattern: random.next())
        }
        let subSecond = EventBuilders.start.addingTimeInterval(Double.random(in: 0 ..< 31_536_000, using: &random))
        let dates = [Date(timeIntervalSinceReferenceDate: anyFinite), subSecond]
        let queue = try DatabaseQueue()
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE sample (at REAL NOT NULL)")
            for date in dates {
                try database.execute(sql: "INSERT INTO sample (at) VALUES (?)", arguments: [ColumnCodec.seconds(date)])
            }
        }
        let stored = try queue.read { try Double.fetchAll($0, sql: "SELECT at FROM sample ORDER BY rowid") }
        #expect(stored.map(ColumnCodec.date(seconds:)) == dates)
    }

    @Test("A date column refuses ±∞ and NaN, which the stamp column keeps as NULL")
    func seconds_refuseNonFiniteDates() throws {
        for seconds in [Double.infinity, -.infinity, .nan] {
            let date = Date(timeIntervalSinceReferenceDate: seconds)
            #expect(throws: LedgerPersistenceError.nonFiniteDate) { try ColumnCodec.seconds(date) }
            #expect(ColumnCodec.finiteSeconds(date) == nil)
        }
        #expect(try ColumnCodec.seconds(Date(timeIntervalSinceReferenceDate: -1.5)) == -1.5)
    }

    @Test("Row timestamps are ISO 8601 UTC text to the millisecond")
    func timestamp_isISO8601ToTheMillisecond() {
        #expect(ColumnCodec.timestamp(EventBuilders.start) == "2026-09-16T05:20:00.000Z")
        #expect(ColumnCodec.timestamp(EventBuilders.start.addingTimeInterval(0.25)) == "2026-09-16T05:20:00.250Z")
    }

    // MARK: Identifiers and seqs

    @Test("An identifier is uuidString text, read back in either case; other text is refused")
    func identifier_isUUIDText() throws {
        let workout = EventBuilders.workoutID
        #expect(ColumnCodec.text(workout) == "00000000-0000-0000-0000-00000000F100")
        let upper: WorkoutID = try ColumnCodec.identifier(ColumnCodec.text(workout))
        let lower: WorkoutID = try ColumnCodec.identifier("00000000-0000-0000-0000-00000000f100")
        #expect(upper == workout && lower == workout)
        #expect(throws: LedgerPersistenceError.malformedIdentifier("singleton")) {
            let _: WorkoutID = try ColumnCodec.identifier("singleton")
        }
    }

    @Test("A seq is stored as its Int64 bit pattern: UInt64.max is −1, and every seq reads back")
    func seq_isStoredAsItsBitPattern() {
        #expect(ColumnCodec.column(seq: .max) == -1)
        #expect(ColumnCodec.column(seq: 1 << 63) == .min)
        #expect(ColumnCodec.column(seq: UInt64(Int64.max)) == .max)
        for seq: UInt64 in [0, 1, UInt64(Int64.max), 1 << 63, .max] {
            #expect(ColumnCodec.seq(column: ColumnCodec.column(seq: seq)) == seq)
        }
    }

    /// `count` stored units, i.e. `count` × 10⁻⁷ g.
    static func units(_ count: Decimal) -> Decimal {
        Decimal(sign: .plus, exponent: -7, significand: count)
    }
}
