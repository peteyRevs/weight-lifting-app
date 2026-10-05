@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The two tiles (specification criterion 8; the body's criteria 8, 9 and 11).
nonisolated extension TodayPresentationTests {
    /// Monday's and Tuesday's workouts of week 1, which moved `pounds` between them.
    static func twoWorkouts(moving pounds: Decimal) throws -> [WorkoutState] {
        try [
            TodayFixtures.workout(2, pounds: pounds - 10000, startedAt: Fixtures.date(2026, 9, 15, hour: 7)),
            TodayFixtures.workout(1, pounds: 10000, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        ]
    }

    /// The tiles at `Fixtures.now` after `twoWorkouts(moving:)`, against `previous` pounds the week before.
    static func stats(
        moving pounds: Decimal,
        previous: Decimal?,
        settings: Settings = Fixtures.settingsLb
    ) throws -> TodayModel.Stats {
        var input = try TodayFixtures.input(program: TodayFixtures.program(), settings: settings)
        input.weekWorkouts = try twoWorkouts(moving: pounds)
        input.previousWeekVolume = previous.map { Volume(weight: .pounds($0), reps: .one) }
        return TodayPresentation.make(input).stats
    }

    @Test("Two sessions of four, 24,180 lb against 22,400 lb: 2/4 and 24.2k, up 8% (criterion 9)")
    func stats_twoOfFourSessions_readTheBriefsExample() throws {
        let stats = try Self.stats(moving: 24180, previous: 22400)
        #expect(stats.sessions.value == "2")
        #expect(stats.sessions.unit == "/4")
        #expect(stats.sessions.caption == "sessions this week")
        #expect(stats.sessions.delta == nil)
        #expect(stats.sessions.accessibilitySummary == "2 of 4 sessions this week")
        #expect(stats.volume.value == "24.2")
        #expect(stats.volume.unit == "k")
        #expect(stats.volume.caption == "lb moved")
        #expect(stats.volume.delta == "+8%")
        #expect(stats.volume.accessibilitySummary == "24,180 lb moved, +8%")
    }

    @Test("The change is signed, with a real minus sign; it is absent with no previous week or an empty one")
    func stats_delta_positiveNegativeHidden() throws {
        // 21,728 against 22,400 is −3%, written with U+2212.
        let down = try Self.stats(moving: 21728, previous: 22400).volume
        #expect(down.delta == "\u{2212}3%")
        #expect(down.accessibilitySummary == "21,728 lb moved, \u{2212}3%")
        let none = try Self.stats(moving: 24180, previous: nil).volume
        #expect(none.delta == nil)
        #expect(none.accessibilitySummary == "24,180 lb moved")
        #expect(try Self.stats(moving: 24180, previous: 0).volume.delta == nil)
    }

    @Test("A change within half a percent reads 0%, with no sign")
    func stats_delta_withinHalfAPercent_readsZero() throws {
        #expect(try Self.stats(moving: 22400, previous: 22400).volume.delta == "0%")
        // 22,300 against 22,400 is −0.45%.
        #expect(try Self.stats(moving: 22300, previous: 22400).volume.delta == "0%")
    }

    @Test("A change too large for Int is clamped and printed, both ways: nothing overflows")
    func stats_delta_beyondInt_isClamped() throws {
        var input = try TodayFixtures.input(program: TodayFixtures.program())
        input.weekWorkouts = try Self.twoWorkouts(moving: 24180)
        input.previousWeekVolume = Volume(gramReps: Decimal(sign: .plus, exponent: -30, significand: 1))
        #expect(TodayPresentation.make(input).stats.volume.delta == "+9,223,372,036,854,775,807%")
        input.previousWeekVolume = Volume(gramReps: Decimal(sign: .minus, exponent: -30, significand: 1))
        #expect(TodayPresentation.make(input).stats.volume.delta == "\u{2212}9,223,372,036,854,775,807%")
    }

    @Test("In kilograms the tile says kg moved and the values convert (criterion 9)")
    func stats_kilograms_convert() throws {
        let volume = try Self.stats(moving: 24180, previous: 22400, settings: Fixtures.settingsKg).volume
        // 24,180 lb is 10,967.86 kg; the change is the same in either unit.
        #expect(volume.value == "11.0")
        #expect(volume.caption == "kg moved")
        #expect(volume.delta == "+8%")
        #expect(volume.accessibilitySummary == "10,968 kg moved, +8%")
    }

    @Test("No volume reads 0 with k, never 0.0 (criterion 8)")
    func zeroVolume_readsZeroK() throws {
        let stats = try TodayPresentation.make(TodayFixtures.input()).stats
        #expect(stats.volume.value == "0")
        #expect(stats.volume.unit == "k")
        #expect(stats.volume.accessibilitySummary == "0 lb moved")
        #expect(stats.sessions.value == "0")
        #expect(stats.sessions.unit == "/4")
    }

    @Test("With no program the tiles read 0/0 and 0k (criterion 8)")
    func noProgram_tilesReadZero() throws {
        let stats = try TodayPresentation.make(TodayFixtures.input(program: nil)).stats
        #expect(stats.sessions.value == "0")
        #expect(stats.sessions.unit == "/0")
        #expect(stats.sessions.accessibilitySummary == "0 of 0 sessions this week")
        #expect(stats.volume.value == "0")
        #expect(stats.volume.unit == "k")
        #expect(stats.volume.delta == nil)
    }

    @Test("Off-schedule sessions count, so the sessions done can pass the sessions planned")
    func stats_offScheduleSessions_canReadFiveOfFour() throws {
        var input = try TodayFixtures.input(now: Fixtures.date(2026, 9, 20, hour: 20))
        input.weekWorkouts = try (0 ..< 5).map { index in
            try TodayFixtures.workout(
                10 + index,
                pounds: 1000,
                startedAt: Fixtures.date(2026, 9, 14 + index, hour: 7)
            )
        }
        let stats = TodayPresentation.make(input).stats
        #expect(stats.sessions.value == "5")
        #expect(stats.sessions.unit == "/4")
        #expect(stats.sessions.accessibilitySummary == "5 of 4 sessions this week")
        #expect(stats.volume.value == "5.0")
    }

    @Test("Two sessions on one day are two sessions and one done mark")
    func stats_twoSessionsOnOneDay_countTwice() throws {
        var input = try TodayFixtures.input()
        input.weekWorkouts = try [
            TodayFixtures.workout(2, pounds: 500, startedAt: Fixtures.date(2026, 9, 14, hour: 18)),
            TodayFixtures.workout(1, pounds: 500, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        ]
        let model = TodayPresentation.make(input)
        #expect(model.stats.sessions.value == "2")
        #expect(model.weekStrip.marks == "D-T-PP-")
    }

    @Test("A week with one session planned speaks of it in the singular")
    func stats_oneSessionPlanned_isSingular() throws {
        var program = try TodayFixtures.program()
        program.weeks[0].schedule = [.wednesday: program.days[TodayFixtures.DayIndex.lowerA].id]
        let stats = try TodayPresentation.make(TodayFixtures.input(program: program)).stats
        #expect(stats.sessions.unit == "/1")
        #expect(stats.sessions.accessibilitySummary == "0 of 1 session this week")
    }

    @Test("With a Sunday week start the tiles count Sunday to Saturday (criterion 11)")
    func weekStartSunday_tilesCountSundayToSaturday() throws {
        // One workout on each Sunday around the Monday-to-Sunday week, and one on Monday.
        let workouts = try [
            TodayFixtures.workout(3, pounds: 3000, startedAt: Fixtures.date(2026, 9, 20, hour: 7)),
            TodayFixtures.workout(2, pounds: 2000, startedAt: Fixtures.date(2026, 9, 14, hour: 7)),
            TodayFixtures.workout(1, pounds: 1000, startedAt: Fixtures.date(2026, 9, 13, hour: 7))
        ]
        var sundayStart = Fixtures.settingsLb
        sundayStart.weekStart = .sunday
        var input = try TodayFixtures.input(program: TodayFixtures.program(), settings: sundayStart)
        input.weekWorkouts = workouts
        let fromSunday = TodayPresentation.make(input)
        // Sunday the 13th and Monday count; Sunday the 20th is next week's.
        #expect(fromSunday.stats.sessions.value == "2")
        #expect(fromSunday.stats.volume.value == "3.0")
        #expect(fromSunday.weekStrip.marks == "DD-T-PP")
        // Sunday the 13th is before the block, so four sessions are planned in these seven days too.
        #expect(fromSunday.stats.sessions.unit == "/4")

        input.settings = Fixtures.settingsLb
        let fromMonday = TodayPresentation.make(input)
        #expect(fromMonday.stats.sessions.value == "2")
        #expect(fromMonday.stats.volume.value == "5.0")
        #expect(fromMonday.weekStrip.marks == "D-T-PPD")
    }

    @Test("A workout handed in that started outside the strip's seven days is not counted")
    func stats_workoutOutsideTheStrip_isNotCounted() throws {
        var input = try TodayFixtures.input()
        input.weekWorkouts = try [
            TodayFixtures.workout(2, pounds: 2000, startedAt: Fixtures.date(2026, 9, 21, minute: 1)),
            TodayFixtures.workout(1, pounds: 1000, startedAt: Fixtures.date(2026, 9, 13, hour: 23, minute: 59))
        ]
        let stats = TodayPresentation.make(input).stats
        #expect(stats.sessions.value == "0")
        #expect(stats.volume.value == "0")
    }

    @Test("The week's volume is summed exactly: 185 lb sets add up to the pound")
    func stats_volume_isSummedExactly() throws {
        var input = try TodayFixtures.input(program: TodayFixtures.program(), settings: Fixtures.settingsKg)
        // Three workouts of 185 lb each: 555 lb is 251.744 kg, not three rounded 83.9 kg.
        input.weekWorkouts = try (0 ..< 3).map { index in
            try TodayFixtures.workout(20 + index, pounds: 185, startedAt: Fixtures.date(2026, 9, 14 + index, hour: 7))
        }
        input.previousWeekVolume = Volume(weight: .pounds(555), reps: .one)
        let volume = TodayPresentation.make(input).stats.volume
        #expect(volume.accessibilitySummary == "252 kg moved, 0%")
        #expect(volume.value == "0.3")
    }
}
