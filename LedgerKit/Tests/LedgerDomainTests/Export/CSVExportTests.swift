import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, criterion 5, N13–N15: the log as CSV, read back with an RFC 4180 reader (`CSVReader`), as a spreadsheet
/// reads it.
@Suite("CSVExport", .tags(.domain))
struct CSVExportTests {
    static let header = [
        "date",
        "time",
        "workout",
        "tag",
        "exercise",
        "set",
        "kind",
        "weight_lb",
        "reps",
        "done",
        "e1rm_lb"
    ]

    /// A finished workout named `name` with one exercise named `exercise` holding `sets`, started at `start`.
    static func workout(
        name: String = "Upper A — Push focus",
        tag: String = "UA",
        exercise: String = "Barbell Bench Press",
        sets: [LoggedSet],
        start: Date = Fixtures.date(2026, 9, 16, hour: 5, minute: 7)
    ) throws -> WorkoutState {
        var row = try Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets)
        row.name = exercise
        var workout = Fixtures.workout([row])
        workout.name = name
        workout.tag = tag
        workout.startedAt = start
        workout.endedAt = start.addingTimeInterval(3600)
        workout.phase = .finished
        return workout
    }

    static func rows(
        _ workouts: [WorkoutState],
        units: Units = .lb,
        calendar: Calendar = Fixtures.calendar
    ) -> [[String]] {
        CSVReader.rows(CSVExport.render(workouts: workouts, units: units, calendar: calendar))
    }

    @Test("An empty log is the header alone, ending with CRLF; the unit is in the weight columns' titles")
    func emptyLog_isTheHeader() {
        #expect(CSVExport.render(workouts: [], units: .lb, calendar: Fixtures.calendar)
            == Self.header.joined(separator: ",") + "\r\n")
        #expect(CSVExport.header(units: .kg)
            .hasPrefix("date,time,workout,tag,exercise,set,kind,weight_kg,reps,done,e1rm_kg"))
    }

    @Test("A set's row: its day, time, names, place, kind, weight, reps, done and estimate")
    func row_holdsEveryColumn() throws {
        let workout = try Self.workout(sets: [
            Fixtures.set(1, pounds: 185, reps: 5),
            Fixtures.set(2, pounds: 185, reps: 5)
        ])
        let rows = Self.rows([workout])
        // 185 lb × 5: 83,914.58845 g × 36 / 32 = 94,404 g, 208.13 lb.
        #expect(rows.count == 3)
        let isTheRow = rows[1] == [
            "2026-09-16", "05:07", "Upper A — Push focus", "UA", "Barbell Bench Press", "1", "working", "185", "5", "1",
            "208.13"
        ]
        #expect(isTheRow, "\(rows[1])")
        #expect(rows[2][5] == "2")
    }

    @Test("Kilograms: every weight in kilograms, to hundredths (225 lb is 102.06 kg)")
    func kilograms_toHundredths() throws {
        let workout = try Self.workout(sets: [Fixtures.set(1, pounds: 225, reps: 13)])
        let rows = Self.rows([workout], units: .kg)
        #expect(rows[0][7] == "weight_kg" && rows[0][10] == "e1rm_kg")
        #expect(rows[1][7] == "102.06")
    }

    @Test("Each kind as stored; a set not done is 0 with no estimate; over 12 reps no estimate")
    func kinds_done_andEstimates() throws {
        let workout = try Self.workout(sets: [
            Fixtures.set(1, pounds: 95, reps: 8, kind: .warmup),
            Fixtures.set(2, pounds: 135, reps: 5, done: false),
            Fixtures.set(3, pounds: 115, reps: 10, kind: .drop),
            Fixtures.set(4, pounds: 100, reps: 15, kind: .added)
        ])
        let rows = Self.rows([workout]).dropFirst()
        #expect(rows.map { $0[6] } == ["warmup", "working", "drop", "added"])
        #expect(rows.map { $0[9] } == ["1", "0", "1", "1"])
        #expect(rows.map { $0[10].isEmpty } == [false, true, false, true])
    }

    @Test("Commas, quotes and line breaks in names are quoted, quotes doubled, and read back whole")
    func names_quotedAndReadBack() throws {
        let name = "Push, \"heavy\"\r\nday"
        let workout = try Self.workout(name: name, exercise: "Row\nwide", sets: [Fixtures.set(1, pounds: 100, reps: 5)])
        let text = CSVExport.render(workouts: [workout], units: .lb, calendar: Fixtures.calendar)
        #expect(text.contains("\"Push, \"\"heavy\"\"\r\nday\""))
        let rows = CSVReader.rows(text)
        #expect(rows.count == 2 && rows[1][2] == name && rows[1][4] == "Row\nwide")
    }

    @Test(
        "N14. A text field that starts like a formula gets a leading apostrophe",
        arguments: ["=", "+", "-", "@", "\t", "\r"]
    )
    func formulaStart_isGuarded(_ start: String) throws {
        let name = start + "HYPERLINK(\"x\")"
        let workout = try Self.workout(
            name: name,
            tag: start,
            exercise: name,
            sets: [Fixtures.set(1, pounds: 100, reps: 5)]
        )
        let row = Self.rows([workout])[1]
        #expect(row[2] == "'" + name && row[3] == "'" + start && row[4] == "'" + name)
        // Numbers are never prefixed.
        #expect(row[7] == "100")
    }

    @Test("Decision #26: the date is the day the workout started in the lifter's calendar, across midnight and DST")
    func dates_areTheStartDayInTheCalendar() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try Fixtures.zone("America/New_York")
        // 23:30 on Saturday 2026-03-07 in New York is 04:30 UTC on Sunday the 8th, the night clocks go forward.
        let lateNight = Fixtures.date(2026, 3, 8, hour: 4, minute: 30)
        // 03:15 EDT on the 8th, just after the change.
        let afterChange = Fixtures.date(2026, 3, 8, hour: 7, minute: 15)
        let rows = try Self.rows([
            Self.workout(sets: [Fixtures.set(1, pounds: 100, reps: 5)], start: lateNight),
            Self.workout(sets: [Fixtures.set(2, pounds: 100, reps: 5)], start: afterChange)
        ], calendar: newYork)
        #expect(rows[1][0] == "2026-03-07" && rows[1][1] == "23:30")
        #expect(rows[2][0] == "2026-03-08" && rows[2][1] == "03:15")
    }

    @Test("The workouts' rows follow in the order given, and lines(for:) is render's part")
    func render_isHeaderThenLines() throws {
        let first = try Self.workout(name: "A", sets: [Fixtures.set(1, pounds: 100, reps: 5)])
        let second = try Self.workout(name: "B", sets: [Fixtures.set(2, pounds: 100, reps: 5)])
        let lines = [first, second].map { CSVExport.lines(for: $0, units: .lb, calendar: Fixtures.calendar) }
        #expect(CSVExport.render(workouts: [first, second], units: .lb, calendar: Fixtures.calendar)
            == CSVExport.header(units: .lb) + lines.joined())
        #expect(CSVExport.byteOrderMark.unicodeScalars.map(\.value) == [0xFEFF])
    }
}

/// The round trip (N13, N14): any name, written and read back by an RFC 4180 reader.
extension CSVExportTests {
    /// Names drawn from scalars that test the quoting: commas, quotes, CR, LF, tabs, formula starts, emoji, Arabic and
    /// Hebrew, an accent that combines with the quote before it.
    static let alphabet: [String] = [
        ",", "\"", "\r", "\n", "\r\n", "\t", "=", "+", "-", "@", " ", "a", "Z", "é", "e\u{301}", "\"\u{301}",
        "🏋️", "👩🏽‍🦰", "مرحبا", "שלום", "\u{200F}", "'", "0", "1.5"
    ]

    @Test(
        "RFC 4180 round trip: any name is read back as it was, guarded when it starts like a formula",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func anyName_roundTrips(_ seed: PropertySeed) throws {
        var generator = seed.generator
        let names = (0 ..< 3).map { _ in
            (0 ..< Int.random(in: 0 ... 8, using: &generator))
                .compactMap { _ in Self.alphabet.randomElement(using: &generator) }.joined()
        }
        let workout = try Self.workout(
            name: names[0],
            tag: names[1],
            exercise: names[2],
            sets: [Fixtures.set(1, pounds: 100, reps: 5)]
        )
        let rows = Self.rows([workout])
        let expected = names.map(CSVExport.textField).map { field in
            // What a reader gives back: the field without its quotes.
            CSVReader.rows(field + "\r\n").first?.first ?? ""
        }
        let guarded = names.map { name in
            name.unicodeScalars.first.map(CSVExport.formulaStarts.contains) == true ? "'" + name : name
        }
        try #require(rows.count == 2, "\(seed): \(names.debugDescription)")
        #expect(rows[1].count == 11, "\(seed)")
        let readBack = Array(rows[1][2 ... 4]) == guarded
        #expect(readBack, "\(seed): \(names.debugDescription)")
        let fieldsReadBack = expected == guarded
        #expect(fieldsReadBack, "\(seed)")
    }
}
