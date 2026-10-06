@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The recent list's corners: the injected zone decides "Today", the session's own workout takes its place by
/// its start, two workouts that started together both show, and volumes keep their separators.
nonisolated extension TodayRecentAdversarialTests {
    @Test("Today is today in the injected zone: 10:30Z on Tuesday is Wednesday in UTC+14 and Tuesday in UTC")
    func today_isTheInjectedZonesDay() throws {
        let start = try Support.moment(Support.civil(2026, 9, 15), 10, 30)
        let now = try Support.moment(Support.civil(2026, 9, 15), 20)
        let workout = try Support.lifted(number: 301, start: start, seconds: 600, lifts: [.pounds(100, 10)])
        let ahead = try #require(TimeZone(secondsFromGMT: 14 * 3600))
        let behind = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        let program = try Support.seed()
        let inKiritimati = try TodayPresentation.make(Support.input(program, now: now, zone: ahead, recent: [workout]))
        #expect(inKiritimati.recent.rows.map(\.meta) == ["Today · 10:00 · 1,000 lb"])
        #expect(inKiritimati.header.date == "Wednesday, September 16")
        let inUTC = try TodayPresentation.make(Support.input(program, now: now, recent: [workout]))
        #expect(inUTC.recent.rows.map(\.meta) == ["Today · 10:00 · 1,000 lb"])
        // 20:00Z is still Tuesday 08:00 at UTC−12, and so is 10:30Z (Monday 22:30): the workout is Monday's.
        let farWest = try TodayPresentation.make(Support.input(program, now: now, zone: behind, recent: [workout]))
        #expect(farWest.recent.rows.map(\.meta) == ["Mon · 10 min · 1,000 lb"])
        #expect(farWest.header.date == "Tuesday, September 15")
    }

    @Test("The session's finished workout joins the list once, in the place its start gives it")
    func finishedSession_takesItsPlaceByItsStart() throws {
        let stored = try Array(Self.workouts(Self.history).dropFirst())
        let now = try Self.now()
        let fresh = try Support.lifted(
            number: 400,
            start: now.addingTimeInterval(-900),
            seconds: 600,
            lifts: [.pounds(50, 2)]
        )
        let newest = try Support.input(Support.seed(), now: now, recent: stored, session: fresh)
        let rows = TodayPresentation.make(newest).recent.rows
        #expect(rows.count == 5)
        #expect(rows.map(\.route) == [.openWorkout(fresh.id)] + stored.prefix(4).map { .openWorkout($0.id) })
        #expect(rows.first?.meta == "Today · 10:00 · 100 lb")
        // Started on Sunday 23:30 and finished after midnight: between Monday's and Sunday morning's.
        let sunday = try Support.moment(Support.civil(2026, 9, 13), 23, 30)
        let late = try Support.lifted(number: 401, start: sunday, seconds: 3900, lifts: [.pounds(50, 2)])
        let between = try Support.input(Support.seed(), now: now, recent: stored, session: late)
        let placed = TodayPresentation.make(between).recent.rows
        #expect(placed.map(\.route).firstIndex(of: .openWorkout(late.id)) == 1)
        #expect(placed.count == 5)
        #expect(placed.dropFirst().first?.meta == "Sun · 65 min · 100 lb")
        // Reported by history as well: once.
        let both = try Support.input(Support.seed(), now: now, recent: [fresh] + stored, session: fresh)
        #expect(TodayPresentation.make(both).recent.rows.count { $0.route == .openWorkout(fresh.id) } == 1)
    }

    @Test("A live or discarded session is not in the list")
    func unfinishedSession_isNotListed() throws {
        let now = try Self.now()
        var live = try Support.lifted(number: 402, start: now.addingTimeInterval(-60), lifts: [.pounds(50, 2)])
        live.phase = .live
        live.endedAt = nil
        var discarded = live
        discarded.phase = .discarded
        for session in [live, discarded] {
            let list = try TodayPresentation.make(Support.input(Support.seed(), now: now, session: session)).recent
            #expect(list.rows.isEmpty)
            #expect(list.emptyMessage == "No sessions yet. Your first workout lands here.")
        }
    }

    @Test("Two workouts that started together are both listed, in the order history gave them")
    func sameStart_listsBoth() throws {
        let start = try Support.moment(Support.civil(2026, 9, 14), 7)
        let first = try Support.lifted(
            number: 410,
            start: start,
            seconds: 1800,
            lifts: [.pounds(100, 10)],
            name: "First"
        )
        let second = try Support.lifted(
            number: 411,
            start: start,
            seconds: 2400,
            lifts: [.pounds(100, 20)],
            name: "Second"
        )
        let list = try TodayPresentation.make(Support.input(Support.seed(), now: Self.now(), recent: [first, second]))
            .recent
        #expect(list.rows.map(\.name) == ["First", "Second"])
        #expect(list.rows.map(\.meta) == ["Mon · 30 min · 1,000 lb", "Mon · 40 min · 2,000 lb"])
    }

    @Test("A row's volume keeps its thousands separators, and nothing done reads 0", arguments: [
        ["0", "0 lb", "0 kg"], ["999", "999 lb", "453 kg"], ["1000000", "1,000,000 lb", "453,592 kg"],
        ["1234567", "1,234,567 lb", "559,990 kg"]
    ])
    func rowVolume_keepsItsSeparators(_ row: [String]) throws {
        let pounds = try #require(Decimal(string: row[0]))
        let start = try Support.moment(Support.civil(2026, 9, 14), 7)
        let workout = try Support.lifted(
            number: 420,
            start: start,
            lifts: [Support.Lift(weight: .pounds(pounds), reps: 1)]
        )
        for units in Units.allCases {
            let input = try Support.input(
                Support.seed(),
                now: Self.now(),
                settings: Support.settings(units),
                recent: [workout]
            )
            let meta = TodayPresentation.make(input).recent.rows.first?.meta
            #expect(meta == "Mon · 60 min · \(units == .lb ? row[1] : row[2])")
        }
    }

    @Test("Lengths between whole minutes, a workout that ends before it starts, and an unsorted list do not trap")
    func oddLengthsAndOrders_stillGiveRows() throws {
        let start = try Support.moment(Support.civil(2026, 9, 14), 7)
        var lines: [String] = []
        for seconds in [59, 119, 58 * 60 + 59, -600] {
            let workout = try Support.lifted(number: 430, start: start, seconds: seconds, lifts: [.pounds(100, 10)])
            let list = try TodayPresentation.make(Support.input(Support.seed(), now: Self.now(), recent: [workout]))
                .recent
            lines.append("\(seconds) s → \(list.rows.first?.meta ?? "no row")")
            #expect(list.rows.count == 1)
        }
        let shuffled = try [3, 0, 4, 1, 2].map { try Self.workouts(Self.history)[$0] }
        let list = try TodayPresentation.make(Support.input(Support.seed(), now: Self.now(), recent: shuffled)).recent
        lines.append("handed days 11, 16, 9, 14, 13 → \(list.rows.map { String($0.meta.prefix(5)) })")
        #expect(list.rows.count == 5)
        print("TodayRecentAdversarialTests observations: \(lines.joined(separator: "; "))")
    }
}
