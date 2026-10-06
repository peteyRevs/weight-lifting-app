@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// What the injected locale and calendar decide, and what they must not: the scan cannot see a formatter that
/// falls back to the device's.
nonisolated extension TodayPurityAdversarialTests {
    static func wednesday() throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16), 20)
    }

    @Test("The date's words are the injected locale's, not the device's", arguments: [
        "fr_FR", "de_DE", "ja_JP", "es_MX", "en_GB"
    ])
    func dateWords_areTheInjectedLocales(_ identifier: String) throws {
        let locale = Locale(identifier: identifier)
        let now = try Self.wednesday()
        let zone = try Support.zone("Pacific/Kiritimati")
        let monday = try Support.moment(Support.civil(2026, 9, 14), 7)
        let workout = try Support.lifted(number: 900, start: monday, lifts: [.pounds(100, 10)])
        var input = try Support.input(Support.seed(), now: now, zone: zone, recent: [workout])
        input.locale = locale
        let model = TodayPresentation.make(input)
        // The tester's own style, with nothing left to the device: 20:00Z is Thursday 10:00 in Kiritimati.
        let style = Date.FormatStyle(locale: locale, calendar: Support.calendar(zone), timeZone: zone)
        #expect(model.header.date == now.formatted(style.weekday(.wide).month(.wide).day()))
        #expect(model.weekStrip[3].accessibilitySummary == model.header.date)
        #expect(model.weekStrip[3].weekday == now.formatted(style.weekday(.narrow)))
        #expect(model.weekStrip[3].date == now.formatted(style.day()))
        #expect(model.recent.rows.first?.meta.hasPrefix(monday.formatted(style.weekday(.abbreviated)) + " · ") == true)
        if identifier != "en_GB" {
            #expect(model.header.date != "Thursday, September 17")
        }
    }

    @Test("The calendar's own locale and first weekday decide nothing")
    func calendarsLocaleAndFirstWeekday_decideNothing() throws {
        let plain = try Support.input(Support.seed(), now: Self.wednesday())
        var odd = plain
        odd.calendar.locale = Locale(identifier: "ar_SA")
        odd.calendar.firstWeekday = 1
        odd.calendar.minimumDaysInFirstWeek = 7
        let isSame = TodayPresentation.make(odd) == TodayPresentation.make(plain)
        #expect(isSame)
        #expect(TodayPresentation.make(odd).header.date == "Wednesday, September 16")
    }

    @Test("Under another calendar the header, the strip and the spoken dates still name the same day", arguments: [
        Calendar.Identifier.buddhist, .japanese, .iso8601, .republicOfChina, .hebrew, .islamicUmmAlQura, .persian
    ])
    func anotherCalendar_namesTheSameDayThroughout(_ identifier: Calendar.Identifier) throws {
        var input = try Support.input(Support.seed(), now: Self.wednesday())
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = Support.utc
        input.calendar = calendar
        let model = TodayPresentation.make(input)
        #expect(model.header.title == "Lower A")
        #expect(model.weekStrip.count == 7)
        let today = model.weekStrip.first { $0.mark == .today }
        #expect(today?.accessibilitySummary == model.header.date)
        let numbersAreSpoken = model.weekStrip.allSatisfy { $0.accessibilitySummary.contains($0.date) }
        #expect(
            numbersAreSpoken,
            "\(model.weekStrip.map(\.date)) against \(model.weekStrip.map(\.accessibilitySummary))"
        )
        let numbers = model.weekStrip.map(\.date)
        print("TodayPurityAdversarialTests calendar \(identifier): \(model.header.date), strip \(numbers)")
    }

    @Test("Loads that sit on a rounding tie are printed as the Domain prints the exact weight", arguments: [
        "0.05", "0.15", "0.35", "2.15", "72.45", "100.05", "0.125", "185.125", "1000000.05", "33.333"
    ])
    func loadsOnATie_arePrintedExactly(_ text: String) throws {
        let value = try #require(Decimal(string: text))
        for units in Units.allCases {
            var program = try Support.seed()
            let load: Weight = units == .lb ? .pounds(value) : .kilograms(value)
            for index in program.days[1].slots.indices {
                program.days[1].slots[index].startLoad = load
                program.days[1].slots[index].progression = .fixed
            }
            let input = try Support.input(program, now: Self.wednesday(), settings: Support.settings(units))
            let rows = try Support.upNext(TodayPresentation.make(input)).rows
            #expect(rows.first?.scheme == "5 × 5 @ \(load.formatted(in: units))")
            let other: Units = units == .lb ? .kg : .lb
            let converted = try Support.input(program, now: Self.wednesday(), settings: Support.settings(other))
            let shown = try Support.upNext(TodayPresentation.make(converted)).rows
            #expect(shown.first?.scheme == "5 × 5 @ \(load.formatted(in: other))")
        }
    }
}
