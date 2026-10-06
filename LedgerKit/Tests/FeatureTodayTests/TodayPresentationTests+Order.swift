@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The order of the week's workouts is not assumed (criterion 13): the same workouts give the same model however
/// they are handed in. `logged_twiceToday_showsTheNewest` hands two of today's oldest first.
nonisolated extension TodayPresentationTests {
    @Test("Two that started at the same instant are told apart by their ids, the same way in any order")
    func logged_twoAtTheSameInstant_showTheSameOneInAnyOrder() throws {
        let program = try TodayFixtures.program()
        let start = Fixtures.date(2026, 9, 16, hour: 4)
        let lowerA = TodayFixtures.DayIndex.lowerA
        let smaller = try Self.finishedSession(61, of: program, weekIndex: 0, dayIndex: lowerA, startedAt: start)
        let larger = try Self.finishedSession(
            62,
            of: program,
            weekIndex: 0,
            dayIndex: lowerA,
            startedAt: start,
            seconds: 600
        )
        // The repository's order: of two that started together, the smaller id first.
        for week in [[smaller, larger], [larger, smaller]] {
            let card = try #require(Self.model(program, now: Fixtures.now, weekWorkouts: week).card.logged)
            #expect(card.action.route == .openWorkout(smaller.id))
            #expect(card.elapsed == "24:22")
        }
    }

    @Test("The same workouts give the same model in any order, with equal starts and starts that are not numbers")
    func make_weekWorkoutsInAnyOrder_giveTheSameModel() throws {
        let program = try TodayFixtures.program()
        let lowerA = TodayFixtures.DayIndex.lowerA
        let today = Fixtures.date(2026, 9, 16, hour: 4)
        let notANumber = Date(timeIntervalSince1970: .nan)
        // By id: an older one, one with no start, the newest, its twin, another with no start, and Monday's.
        // The ids are chosen against the starts, so that an order by id alone would put an older one first.
        var workouts = try [
            Self.finishedSession(
                61,
                of: program,
                weekIndex: 0,
                dayIndex: lowerA,
                startedAt: today.addingTimeInterval(-60)
            ),
            Self.finishedSession(62, of: program, weekIndex: 0, dayIndex: lowerA, startedAt: notANumber),
            Self.finishedSession(63, of: program, weekIndex: 0, dayIndex: lowerA, startedAt: today, seconds: 600),
            Self.finishedSession(64, of: program, weekIndex: 0, dayIndex: lowerA, startedAt: today),
            Self.finishedSession(65, of: program, weekIndex: 0, dayIndex: lowerA, startedAt: notANumber, seconds: 60),
            TodayFixtures.workout(66, pounds: 1000, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        ]
        var generator = SeededGenerator(seed: 13)
        let expected = try Self.model(program, now: Fixtures.now, weekWorkouts: workouts)
        #expect(expected.card.logged?.action.route == .openWorkout(WorkoutID(Fixtures.uuid(63))))
        #expect(expected.card.logged?.elapsed == "10:00")
        for _ in 0 ..< 40 {
            workouts.shuffle(using: &generator)
            let isSame = try Self.model(program, now: Fixtures.now, weekWorkouts: workouts) == expected
            #expect(isSame, "handed in as \(workouts.map { $0.id.rawValue.uuidString.suffix(2) })")
        }
    }
}
