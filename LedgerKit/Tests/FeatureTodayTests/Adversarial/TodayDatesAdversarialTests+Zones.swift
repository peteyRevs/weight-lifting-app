@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The weekdays a card names, in zones far from UTC and across a day whose midnight the clocks skip.
nonisolated extension TodayDatesAdversarialTests {
    static let farZones = [
        "Pacific/Kiritimati", "Etc/GMT+12", "Pacific/Chatham", "Asia/Kathmandu", "Australia/Lord_Howe",
        "America/Santiago"
    ]

    @Test(
        "The weekdays in the rest-day body, the Next line and a recent row are the injected zone's",
        arguments: farZones
    )
    func namedWeekdays_areTheInjectedZones(_ identifier: String) throws {
        let zone = try Support.zone(identifier)
        let program = try Support.seed()
        let thursday = try Support.moment(Support.civil(2026, 9, 17), 0, 0, 1, in: zone)
        let rest = try Support.rest(TodayPresentation.make(Support.input(program, now: thursday, zone: zone)))
        #expect(rest.body == "Nothing scheduled for Thursday in week 1. Next up is Friday.")
        let sunday = try Support.moment(Support.civil(2026, 9, 20), 23, 59, 59, in: zone)
        let last = try Support.rest(TodayPresentation.make(Support.input(program, now: sunday, zone: zone)))
        #expect(last.body == "Nothing scheduled for Sunday in week 1. Next up is next Monday.")
        let early = try Support.moment(Support.civil(2026, 9, 16), 0, 0, 1, in: zone)
        let done = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 950, start: early),
            after: 600
        )
        let late = try Support.moment(Support.civil(2026, 9, 14), 23, 50, in: zone)
        let monday = try Support.lifted(number: 951, start: late, seconds: 1800, lifts: [.pounds(100, 10)])
        let now = try Support.moment(Support.civil(2026, 9, 16), 23, 59, 59, in: zone)
        let input = try Support.input(program, now: now, zone: zone, week: [done, monday], recent: [done, monday])
        let model = TodayPresentation.make(input)
        #expect(try Support.logged(model).next == "Next: Friday · UB")
        #expect(model.recent.rows.map(\.meta) == ["Today · 10:00 · 30,370 lb", "Mon · 30 min · 1,000 lb"])
        #expect(model.weekStrip.map(\.mark) == [.done, .rest, .done, .rest, .planned, .planned, .rest])
    }

    @Test("A next session on the day whose midnight Santiago skips is still named by its own weekday")
    func nextSessionOnADayWithoutMidnight_isNamed() throws {
        // Chile's clocks go from 24:00 on Saturday 2026-09-05 to 01:00 on Sunday 09-06.
        let zone = try Support.zone("America/Santiago")
        var program = try Support.seed(start: Support.civil(2026, 8, 31))
        program.weeks[0].schedule[.saturday] = nil
        program.weeks[0].schedule[.sunday] = program.days[3].id
        let saturday = try Support.moment(Support.civil(2026, 9, 5), 23, 59, 59, in: zone)
        let model = try TodayPresentation.make(Support.input(program, now: saturday, zone: zone))
        #expect(model.header.date == "Saturday, September 5")
        #expect(try Support.rest(model).body == "Nothing scheduled for Saturday in week 1. Next up is Sunday.")
        #expect(model.weekStrip.last?.accessibilitySummary == "Sunday, September 6")
        #expect(model.weekStrip.last?.date == "6")
        #expect(model.weekStrip.last?.mark == .planned)
        let sunday = try TodayPresentation.make(Support.input(program, now: saturday.addingTimeInterval(1), zone: zone))
        #expect(sunday.header.date == "Sunday, September 6")
        #expect(sunday.header.title == "Lower B")
        #expect(sunday.weekStrip.last?.mark == .today)
    }
}
