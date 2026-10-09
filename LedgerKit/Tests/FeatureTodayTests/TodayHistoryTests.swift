@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5, criterion 2: the stretches of time the store reads, and that the week is one read.
@Suite("TodayHistory", .tags(.feature))
struct TodayHistoryTests {
    private static func ranges(
        _ program: Program?,
        now: Date = Fixtures.now,
        weekStart: Weekday = .monday
    ) -> TodayHistory.Ranges? {
        var settings = Fixtures.settingsLb
        settings.weekStart = weekStart
        return TodayHistory.ranges(program: program, settings: settings, now: now, calendar: Fixtures.calendar)
    }

    private static func day(_ month: Int, _ day: Int) -> Date {
        Fixtures.date(2026, month, day)
    }

    @Test("A block that began on the week's first day: the two weeks are the same seven days")
    func alignedWeeks_areOneWeek() throws {
        let ranges = try #require(Self.ranges(TodayFixtures.program()))
        #expect(ranges.week == Self.day(9, 14) ..< Self.day(9, 21))
        #expect(ranges.previousWeek == Self.day(9, 7) ..< Self.day(9, 14))
    }

    @Test("A block that began midweek: one stretch from the earlier start to the later end, in either order")
    func misalignedWeeks_areOneStretch() throws {
        // Begun on Wednesday the 9th: the program week of the 16th is Wed 16 to Tue 22, after the stats week's start.
        let wednesday = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 9))
        #expect(Self.ranges(wednesday)?.week == Self.day(9, 14) ..< Self.day(9, 23))
        // Begun on Friday the 11th: the program week of the 16th is Fri 11 to Thu 17, before the stats week's start.
        let friday = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 11))
        #expect(Self.ranges(friday)?.week == Self.day(9, 11) ..< Self.day(9, 21))
        // The week before is the stats week's, whatever the block's.
        #expect(Self.ranges(friday)?.previousWeek == Self.day(9, 7) ..< Self.day(9, 14))
    }

    @Test("The stats week follows the settings' week start")
    func weekStart_movesTheStatsWeek() throws {
        let ranges = try #require(try Self.ranges(TodayFixtures.program(), weekStart: .sunday))
        #expect(ranges.week == Self.day(9, 13) ..< Self.day(9, 21), "Sun 13 to Sat 19, and the program week to Sun 20")
        #expect(ranges.previousWeek == Self.day(9, 6) ..< Self.day(9, 13))
    }

    @Test("With no program, and after the block, the stats week stands alone")
    func noProgramOrBlockComplete_isTheStatsWeek() throws {
        #expect(Self.ranges(nil)?.week == Self.day(9, 14) ..< Self.day(9, 21))
        // The eight weeks from Wednesday 2026-09-09 end on Tuesday 2026-11-03; Thursday the 5th is past them.
        let program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 9))
        #expect(Self.ranges(program, now: Self.day(11, 5))?.week == Self.day(11, 2) ..< Self.day(11, 9))
    }

    @Test("Before the block begins, its first week joins the stats week")
    func beforeTheBlock_readsToTheEndOfWeekOne() throws {
        let program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 23))
        #expect(Self.ranges(program)?.week == Self.day(9, 14) ..< Self.day(9, 30))
    }

    @Test("A moment with no calendar date reads nothing, and the week is empty")
    func momentWithoutADate_readsNothing() async throws {
        let beyond = Date(timeIntervalSince1970: 400_000_000_000)
        #expect(Self.ranges(nil, now: beyond) == nil)
        let stores = try InMemoryStores(seed: .preview())
        let history = try await TodayHistory.read(nil, workouts: stores.workouts, stats: stores.stats)
        #expect(history.weekWorkouts.isEmpty)
        #expect(history.previousWeekVolume == nil)
    }

    @Test("The read hands in the workouts of the stretch, each once, and the volume of the week before")
    func read_handsInEachWorkoutOnce() async throws {
        let stores = try InMemoryStores(seed: .preview())
        let ranges = try #require(try Self.ranges(Fixtures.seedProgram()))
        let history = try await TodayHistory.read(ranges, workouts: stores.workouts, stats: stores.stats)
        // The seed history up to Wednesday 05:20: Monday's Upper A alone this week.
        #expect(history.weekWorkouts.map(\.name) == ["Upper A — Push focus"])
        #expect(Set(history.weekWorkouts.map(\.id)).count == history.weekWorkouts.count)
        let previous = try await stores.stats.weeklyVolume(in: ranges.previousWeek)
        #expect(history.previousWeekVolume == previous)
        #expect(previous > .zero)
    }
}
