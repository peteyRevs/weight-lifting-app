import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `CSVExport`'s dates by the start day, and the seeded round trip.
extension CSVExportAdversarialTests {
    // MARK: - Dates (decision #26)

    @Test("date is the start day and time the start's HH:mm in the lifter's zone, across midnight", arguments: [
        // 23:50 in New York is 03:50 UTC the next day.
        ("America/New_York", Fixtures.date(2026, 9, 16, hour: 3, minute: 50), "2026-09-15", "23:50"),
        // 00:05 in Kiritimati (+14) is 10:05 UTC the day before.
        ("Pacific/Kiritimati", Fixtures.date(2026, 9, 15, hour: 10, minute: 5), "2026-09-16", "00:05"),
        ("Pacific/Pago_Pago", Fixtures.date(2026, 9, 16, hour: 10, minute: 59), "2026-09-15", "23:59"),
        ("UTC", Fixtures.date(2026, 1, 1, hour: 0, minute: 0), "2026-01-01", "00:00"),
        ("Asia/Kolkata", Fixtures.date(2026, 12, 31, hour: 18, minute: 30), "2027-01-01", "00:00")
    ])
    func dates_byStartDay(zone: String, start: Date, day: String, time: String) throws {
        // The workout ends an hour later, on the next day in most of these: the start day still names it.
        let rows = try Self.rows(
            [Self.workout(start: start, [("Bench", [.init(100, 5)])])],
            calendar: Self.calendar(zone)
        )
        #expect(rows.last?[0] == day)
        #expect(rows.last?[1] == time)
    }

    @Test("Daylight saving: the hour that repeats reads 01:30 twice, the skipped hour never appears")
    func dates_acrossDaylightSaving() throws {
        let newYork = Self.calendar("America/New_York")
        // 2026-11-01: 01:30 EDT is 05:30 UTC, 01:30 EST is 06:30 UTC. 2026-03-08: 01:59 EST is 06:59 UTC, then 03:00.
        let starts = [
            Fixtures.date(2026, 11, 1, hour: 5, minute: 30), Fixtures.date(2026, 11, 1, hour: 6, minute: 30),
            Fixtures.date(2026, 3, 8, hour: 6, minute: 59), Fixtures.date(2026, 3, 8, hour: 7, minute: 0)
        ]
        let workouts = starts.enumerated().map { index, start in
            Self.workout(number: index + 1, start: start, [("Bench", [.init(100, 5)])])
        }
        let rows = try Self.rows(workouts, calendar: newYork).dropFirst()
        #expect(rows.map { $0[0] } == ["2026-11-01", "2026-11-01", "2026-03-08", "2026-03-08"])
        #expect(rows.map { $0[1] } == ["01:30", "01:30", "01:59", "03:00"])
    }

    @Test("A non-Gregorian calendar still writes the ISO Gregorian day (Buddhist, Japanese, Persian)", arguments: [
        Calendar.Identifier.buddhist, .japanese, .persian, .islamicUmmAlQura
    ])
    func dates_nonGregorianCalendar(identifier: Calendar.Identifier) throws {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = Fixtures.utc
        let rows = try Self.rows([Self.workout([("Bench", [.init(100, 5)])])], calendar: calendar)
        #expect(rows.last?[0] == "2026-09-16")
        #expect(rows.last?[1] == "05:20")
    }

    @Test("render writes workouts in the order given, and equals the header plus each workout's lines")
    func render_isHeaderPlusLines() {
        let first = Self.workout(number: 1, start: Fixtures.date(2026, 9, 1), [("Bench", [.init(100, 5)])])
        let second = Self.workout(number: 2, start: Fixtures.date(2026, 8, 1), [("Row", [.init(90, 5)])])
        let text = CSVExport.render(workouts: [first, second], units: .kg, calendar: Fixtures.calendar)
        let built = CSVExport.header(units: .kg) + CSVExport.lines(for: first, units: .kg, calendar: Fixtures.calendar)
            + CSVExport.lines(for: second, units: .kg, calendar: Fixtures.calendar)
        #expect(text == built)
    }

    // MARK: - Round trip (property)

    /// The scalars names are drawn from: letters, every character N13 and N14 care about, emoji with modifiers and
    /// joiners, Arabic and Hebrew, bidi marks, combining marks, and "é" precomposed and not.
    static let alphabet: [String] = [
        "a", "B", "z", " ", ",", "\"", "\r", "\n", "\r\n", "\t", "=", "+", "-", "@", "'", ";",
        "👍🏽", "👨‍👩‍👧", "🏋️‍♀️", "سكوات", "דדליפט", "\u{200F}", "\u{202E}", "\u{0301}", "é", "e\u{0301}", "ß", "中",
        "\u{FEFF}", "0", "9", "."
    ]

    static func randomName(_ generator: inout SeededGenerator) -> String {
        let length = Int.random(in: 0 ... 12, using: &generator)
        return (0 ..< length).map { _ in alphabet.randomElement(using: &generator) ?? "a" }.joined()
    }

    /// What a text field should read back as: the name, with a leading `'` when it starts with a formula character.
    static func guarded(_ name: String) -> [Unicode.Scalar] {
        let starts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        let first = name.unicodeScalars.first
        return (first.map(starts.contains) == true ? ["'"] : []) + Array(name.unicodeScalars)
    }

    @Test(
        "Property: random names (emoji, RTL, quotes, commas, line breaks) read back as written, guarded",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func property_roundTrip(seed: PropertySeed) throws {
        var generator = seed.generator
        var workouts: [WorkoutState] = []
        var expected: [[[Unicode.Scalar]]] = []
        for number in 0 ..< Int.random(in: 1 ... 3, using: &generator) {
            let name = Self.randomName(&generator)
            let tag = Self.randomName(&generator)
            let exercises = (0 ..< Int.random(in: 1 ... 3, using: &generator)).map { _ in
                (Self.randomName(&generator), [Seeders.SetSpec(100, 5)])
            }
            workouts.append(Self.workout(number: number + 1, name: name, tag: tag, exercises))
            for exercise in exercises {
                expected.append([Self.guarded(name), Self.guarded(tag), Self.guarded(exercise.0)])
            }
        }
        let text = CSVExport.render(workouts: workouts, units: .lb, calendar: Fixtures.calendar)
        let rows = try #require(Self.read(text), "\(seed): not RFC 4180")
        #expect(rows.count == expected.count + 1, "\(seed): row count")
        for (row, fields) in zip(rows.dropFirst(), expected) {
            #expect(row.count == 11, "\(seed): field count")
            let fieldsRead = [2, 3, 4].map { Array(row[$0]) }
            #expect(fieldsRead == fields, "\(seed): fields differ")
        }
    }

    @Test(
        "Property: LedgerTestSupport's CSVReader agrees with this reader on every seeded file",
        .tags(.property),
        arguments: PropertySeed.all.prefix(50)
    )
    func property_readersAgree(seed: PropertySeed) {
        var generator = seed.generator
        let workout = Self.workout(name: Self.randomName(&generator), tag: Self.randomName(&generator), [
            (Self.randomName(&generator), [.init(100, 5)])
        ])
        let text = CSVExport.render(workouts: [workout], units: .lb, calendar: Fixtures.calendar)
        let ours = Self.read(text)?.map { $0.map { Array($0) } }
        let theirs = CSVReader.rows(text).map { $0.map { Array($0.unicodeScalars) } }
        #expect(ours == theirs, "\(seed)")
    }
}
