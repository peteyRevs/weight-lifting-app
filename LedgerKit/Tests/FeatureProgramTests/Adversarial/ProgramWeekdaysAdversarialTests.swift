@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: the schedule strip's order, letters and spoken names (criterion 3: "the seven
/// cells in the order of the settings' week start, each with the weekday's letter from the injected calendar
/// and locale"; behaviour 20). The letters of English, German and Japanese are written here by hand, Monday
/// first; Arabic's are asked of a `DateFormatter` on seven known dates, which is not how a model would read them.
@Suite("Adversarial F11 S5 · week starts, calendars and locales", .tags(.feature))
nonisolated struct ProgramWeekdaysAdversarialTests {
    struct Language: Sendable, CustomTestStringConvertible {
        let identifier: String
        /// Monday to Sunday.
        let letters: [String]
        let names: [String]

        var testDescription: String {
            identifier
        }
    }

    static let languages = [
        Language(
            identifier: "en_US",
            letters: ["M", "T", "W", "T", "F", "S", "S"],
            names: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        ),
        Language(
            identifier: "de_DE",
            letters: ["M", "D", "M", "D", "F", "S", "S"],
            names: ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
        ),
        Language(
            identifier: "ja_JP",
            letters: ["月", "火", "水", "木", "金", "土", "日"],
            names: ["月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日"]
        )
    ]

    /// The strip of the seed's week 1 as "weekday letter label" per cell.
    static func strip(_ input: ProgramBuilderInput) -> [String] {
        ProgramPresentation.make(input).week.cells.map { "\($0.weekday) \($0.letter) \($0.label)" }
    }

    /// Monday 2026-08-17 and the six days after it, formatted with `pattern` in `locale`.
    static func formatted(_ pattern: String, locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = AdvProgram.calendar(locale: locale)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = locale
        formatter.dateFormat = pattern
        return (17 ... 23).map { formatter.string(from: Fixtures.date(2026, 8, $0, hour: 12)) }
    }

    @Test("A Sunday week start draws S REST first and moves no day to another weekday")
    func sundayStart_seed_rotatesTheStripOnly() throws {
        var input = try AdvProgram.seed()
        input.settings.weekStart = .sunday
        let week = ProgramPresentation.make(input).week
        let strip = week.cells.map { "\($0.letter) \($0.label)" }.joined(separator: " · ")
        #expect(strip == "S REST · M UA · T REST · W LA · T REST · F UB · S LB")
        #expect(week.cells.map(\.weekday) == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        let actions = week.cells.map(\.action)
        let becomes = week.cells.map { AdvScreen.next(input.program, place: 0, weekday: $0.weekday)?.id }
        #expect(becomes.map { $0 == nil } == [false, false, false, false, false, false, true], "LB is the last day")
        #expect(actions == zip(week.cells, becomes).map {
            .edit(.setSchedule(week: 0, weekday: $0.weekday, day: $1), notice: nil)
        })
        #expect(week.cells.map(\.spokenLabel).first == "Sunday")
    }

    @Test(
        "Every week start gives the seven weekdays from it, each cell with its own letter and name",
        arguments: Weekday.allCases
    )
    func everyWeekStart_ordersTheCellsFromIt(start: Weekday) throws {
        var input = try AdvProgram.seed()
        input.settings.weekStart = start
        let cells = ProgramPresentation.make(input).week.cells
        let order = AdvScreen.order(from: start)
        #expect(cells.map(\.weekday) == order)
        #expect(cells.map(\.letter) == order.map { Self.languages[0].letters[$0.rawValue - 1] })
        #expect(cells.map(\.spokenLabel) == order.map { Self.languages[0].names[$0.rawValue - 1] })
        let seed = ["monday": "UA", "wednesday": "LA", "friday": "UB", "saturday": "LB"]
        #expect(cells.map(\.label) == order.map { seed["\($0)"] ?? "REST" })
    }

    @Test("The letters and spoken names are the locale's, Monday first", arguments: languages)
    func lettersAndNames_followTheLocale(language: Language) throws {
        let locale = Locale(identifier: language.identifier)
        var input = try AdvProgram.seed()
        input.locale = locale
        input.calendar = AdvProgram.calendar(locale: locale)
        let cells = ProgramPresentation.make(input).week.cells
        #expect(cells.map(\.letter) == language.letters)
        #expect(cells.map(\.spokenLabel) == language.names)
    }

    @Test("Arabic letters and names are the ones a date formatter gives for seven known dates")
    func arabic_lettersAndNames_matchAFormatter() throws {
        let locale = Locale(identifier: "ar_SA")
        var input = try AdvProgram.seed()
        input.locale = locale
        input.calendar = AdvProgram.calendar(firstWeekday: 7, locale: locale)
        let cells = ProgramPresentation.make(input).week.cells
        #expect(cells.map(\.spokenLabel) == Self.formatted("EEEE", locale: locale))
        let letters = cells.map(\.letter)
        let either = letters == Self.formatted("EEEEE", locale: locale) || letters == Self.formatted(
            "ccccc",
            locale: locale
        )
        #expect(either, "\(letters)")
        #expect(Set(letters).count == 7, "Arabic's seven letters differ: \(letters)")
        #expect(cells.map(\.weekday).first == .monday, "the settings order the strip, not the Saturday-first calendar")
        #expect(cells.map(\.label) == ["UA", "REST", "LA", "REST", "UB", "LB", "REST"])
    }

    @Test("The calendar's first weekday, time zone and own locale change nothing: the settings and the locale decide")
    func calendarsOtherSettings_changeNothing() throws {
        let base = try AdvProgram.seed()
        let expected = Self.strip(base)
        var found: [String] = []
        for first in 1 ... 7 {
            for zone in ["UTC", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kathmandu"] {
                for own in [Locale(identifier: "de_DE"), Locale(identifier: "ja_JP"), nil] {
                    var input = base
                    input.calendar = AdvProgram.calendar(firstWeekday: first, locale: own, zone: zone)
                    let same = ProgramPresentation.make(input) == ProgramPresentation.make(base)
                    if !same {
                        let got = Self.strip(input)
                        found.append("first \(first), \(zone), \(own?.identifier ?? "none"): \(got.prefix(2))")
                    }
                }
            }
        }
        #expect(expected.first == "monday M UA")
        #expect(found.isEmpty, "\(found.prefix(3))")
    }

    @Test("A calendar that is not Gregorian still gives seven letters and names at the right weekdays", arguments: [
        Calendar.Identifier.buddhist, .hebrew, .islamicUmmAlQura, .japanese, .persian, .iso8601, .chinese
    ])
    func otherCalendars_keepTheWeekdays(identifier: Calendar.Identifier) throws {
        var input = try AdvProgram.seed()
        var calendar = Calendar(identifier: identifier)
        calendar.locale = AdvProgram.english
        input.calendar = calendar
        let cells = ProgramPresentation.make(input).week.cells
        #expect(cells.map(\.letter) == Self.languages[0].letters)
        #expect(cells.map(\.spokenLabel) == Self.languages[0].names)
    }

    @Test("What VoiceOver reads for a cell agrees with what is drawn, in every week of the seed")
    func cellsSpokenTexts_agreeWithTheDrawnOnes() throws {
        var found: [String] = []
        var hints: Set<String> = []
        for week in 0 ..< 8 {
            let input = try AdvProgram.seed(week: week)
            for cell in ProgramPresentation.make(input).week.cells {
                let day = input.program.weeks[week].schedule[cell.weekday].flatMap { id in
                    input.program.days.first { $0.id == id }
                }
                let value = day?.shortTitle ?? "Rest"
                if cell.spokenValue != value || cell.isRest != (day == nil) || cell.label != (day?.tag ?? "REST") {
                    found.append("week \(week) \(cell.weekday): \(cell.spokenValue) for \(cell.label)")
                }
                hints.insert(cell.spokenHint ?? "")
            }
        }
        #expect(found.isEmpty, "\(found.prefix(4))")
        #expect(hints.count == 1, "one hint for every cell: \(hints)")
        #expect(hints.first?.localizedCaseInsensitiveContains("assign") == true, "the brief: double-tap to assign")
    }
}
