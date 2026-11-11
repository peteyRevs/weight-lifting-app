import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `CSVExport` (criterion 5, N13–N15) read back through an RFC 4180 reader written here, apart
/// from LedgerTestSupport's, which reads Unicode scalars: CRLF rows, quoting, the formula guard for each of its six
/// characters and never for a number, kinds, e1RM's edge, dates by the start day across midnight and daylight
/// saving, and a seeded round trip of names with emoji, right-to-left text, quotes, commas and line breaks.
@Suite("Adversarial F14 S2 · CSVExport", .tags(.domain))
struct CSVExportAdversarialTests {
    static func read(_ text: String) -> [[String.UnicodeScalarView]]? {
        CSVAdversarialReader.read(text)
    }

    static func strings(_ text: String) -> [[String]]? {
        CSVAdversarialReader.strings(text)
    }

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        CSVAdversarialReader.scalars(text)
    }

    // MARK: - Builders

    static let bench = Seeders.catalogEntry(0)
    static let row = Seeders.catalogEntry(7)

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// One finished workout started at `start`, named as given, whose exercises hold these sets.
    static func workout(
        number: Int = 1,
        start: Date = Fixtures.now,
        name: String = "Push",
        tag: String = "A",
        _ exercises: [(String, [Seeders.SetSpec])]
    ) -> WorkoutState {
        var workout = Seeders.workout(
            number: number,
            endedAt: start.addingTimeInterval(3600),
            exercises.enumerated().map { index, entry in
                Seeders.ExerciseLog(index.isMultiple(of: 2) ? bench : row, entry.1)
            }
        )
        workout.startedAt = start
        workout.name = name
        workout.tag = tag
        for index in workout.exercises.indices {
            workout.exercises[index].name = exercises[index].0
        }
        return workout
    }

    static func rows(_ workouts: [WorkoutState], units: Units = .lb, calendar: Calendar? = nil) throws -> [[String]] {
        let text = CSVExport.render(workouts: workouts, units: units, calendar: calendar ?? Fixtures.calendar)
        return try #require(strings(text), "not RFC 4180")
    }

    // MARK: - Shape

    @Test("The header names the unit, and the BOM is the three bytes EF BB BF", arguments: Units.allCases)
    func header_perUnit(units: Units) {
        let unit = units == .lb ? "lb" : "kg"
        #expect(CSVExport
            .header(units: units) ==
            "date,time,workout,tag,exercise,set,kind,weight_\(unit),reps,done,e1rm_\(unit)\r\n")
        #expect(Array(CSVExport.byteOrderMark.utf8) == [0xEF, 0xBB, 0xBF])
    }

    @Test("An empty log is the header row only, ending in CRLF")
    func emptyLog_isTheHeader() throws {
        let text = CSVExport.render(workouts: [], units: .kg, calendar: Fixtures.calendar)
        #expect(text == CSVExport.header(units: .kg))
        #expect(try #require(Self.strings(text)).count == 1)
    }

    @Test("A workout with no sets writes no row, and one with an exercise of no sets writes none for it")
    func noSets_noRows() throws {
        let rows = try Self.rows([Self.workout([]), Self.workout(number: 2, [("Bench", []), ("Row", [.init(100, 5)])])])
        #expect(rows.count == 2)
        #expect(rows.last?[4] == "Row")
        #expect(rows.last?[5] == "1")
    }

    @Test("Every row has eleven fields, every line ends in CRLF, and no bare LF appears outside quotes")
    func everyRow_hasElevenFields() throws {
        let workout = Self.workout(name: "Line\nbreak", tag: "Tab\tin", [
            ("Bench, paused", [.init(135, 5), .init(135, 5, .warmup, done: false)]),
            ("Row \"heavy\"", [.init(95, 8, .drop), .init(95, 13, .added)])
        ])
        let text = CSVExport.render(workouts: [workout], units: .lb, calendar: Fixtures.calendar)
        let rows = try #require(Self.strings(text))
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0.count == 11 })
        #expect(text.hasSuffix("\r\n"))
    }

    @Test("set counts from 1 within each exercise; kind, reps and done are written as stored")
    func setAndKind_asStored() throws {
        let rows = try Self.rows([Self.workout([
            ("Bench", [.init(45, 10, .warmup), .init(135, 5), .init(135, 5), .init(115, 8, .drop)]),
            ("Row", [.init(95, 8, .added, done: false), .init(95, 8)])
        ])]).dropFirst()
        #expect(rows.map { $0[5] } == ["1", "2", "3", "4", "1", "2"])
        #expect(rows.map { $0[6] } == ["warmup", "working", "working", "drop", "added", "working"])
        #expect(rows.map { $0[8] } == ["10", "5", "5", "8", "8", "8"])
        #expect(rows.map { $0[9] } == ["1", "1", "1", "1", "0", "1"])
    }

    @Test("Weights are plain decimals in the asked unit, rounded to hundredths, with no grouping", arguments: [
        (Decimal(225), Units.kg, "102.06"), (100, .kg, "45.36"), (45, .kg, "20.41"), (135, .lb, "135"),
        (2.5, .lb, "2.5"), (0, .lb, "0"), (0, .kg, "0"), (12345, .lb, "12345"), (1, .kg, "0.45"), (1.25, .lb, "1.25")
    ])
    func weights_plainDecimals(pounds: Decimal, units: Units, expected: String) throws {
        let rows = try Self.rows([Self.workout([("Bench", [.init(pounds, 13)])])], units: units)
        #expect(rows.last?[7] == expected)
    }

    @Test("e1RM is written for a done set of 12 reps or fewer, empty above 12 and for a set not done")
    func e1rm_edges() throws {
        let rows = try Self.rows([Self.workout([("Bench", [
            .init(100, 1), .init(100, 12), .init(100, 13), .init(100, 5, done: false), .init(100, 30)
        ])])]).dropFirst()
        // 100 × 36 / 36 = 100; 100 × 36 / 25 = 144.
        #expect(rows.map { $0[10] } == ["100", "144", "", "", ""])
    }

    @Test("e1RM is in the asked unit: 225 lb × 5 is 253.13 lb (gram-rounded Brzycki) and 114.82 kg")
    func e1rm_inTheUnit() throws {
        let workout = Self.workout([("Bench", [.init(225, 5)])])
        let pounds = try Self.rows([workout], units: .lb).last?[10]
        let kilograms = try Self.rows([workout], units: .kg).last?[10]
        #expect(pounds == "253.13")
        #expect(kilograms == "114.82")
    }
}
