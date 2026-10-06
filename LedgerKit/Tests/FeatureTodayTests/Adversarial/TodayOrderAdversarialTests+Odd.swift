@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 13 where an order is hardest to keep: starts that are not moments, and an id handed in twice.
nonisolated extension TodayOrderAdversarialTests {
    /// Lower A of week 1 of the seed, finished, started at each of `starts`, numbered from `number`.
    static func lowerAs(_ program: Program, number: Int, starts: [Date]) throws -> [WorkoutState] {
        let lowerA = try Support.day("LA", in: program)
        let source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: lowerA.id)
        return try starts.enumerated().map { index, start in
            try Support.lifted(
                number: number + index,
                start: start,
                seconds: 600 + 60 * index,
                lifts: [.pounds(100, 1 + index)],
                source: source
            )
        }
    }

    @Test("Starts that are not a number, infinite or ages away still give one model in every order", arguments: 0 ..< 3)
    func oddStarts_giveOneModelInEveryOrder(_ group: Int) throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16), 12)
        let morning = now.addingTimeInterval(-3 * 3600)
        let never = Date(timeIntervalSinceReferenceDate: .nan)
        let groups: [[Date]] = [
            [never, never, Date(timeIntervalSinceReferenceDate: .infinity), morning, morning],
            [never, Date(timeIntervalSinceReferenceDate: -.infinity), .distantPast, morning, morning],
            [.distantFuture, Date(timeIntervalSinceReferenceDate: .infinity), never, morning, .distantFuture]
        ]
        let workouts = try Self.lowerAs(program, number: 60, starts: groups[group])
        let input = try Support.input(program, now: now, week: workouts)
        let different = Self.ordersThatDiffer(input, among: Self.orders(of: workouts))
        #expect(different == 0, "\(different) of 120 orders give another model")
        let card = try Support.logged(TodayPresentation.make(input))
        let todays = workouts.filter { $0.startedAt == morning }.map { TodayRoute.openWorkout($0.id) }
        #expect(todays.contains(card.action.route))
    }

    @Test("One id handed in twice with different sets: a card either way, and what it shows is printed")
    func sameIdTwice_stillGivesACard() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16), 12)
        let live = try Support.live(program, week: 0, tag: "LA", number: 70, start: now.addingTimeInterval(-3000))
        let copies = [Support.finished(live, after: 1000, done: 9), Support.finished(live, after: 1462)]
        let shown = try [copies, copies.reversed()].map { week in
            try Support.logged(TodayPresentation.make(Support.input(program, now: now, week: Array(week)))).stats
        }
        #expect(shown.allSatisfy { $0.hasSuffix(" lb moved") })
        // The same copy twice, as two reads of overlapping weeks would hand it in if nothing merged them.
        let twice = try TodayPresentation.make(Support.input(program, now: now, week: [copies[1], copies[1]])).stats
        #expect(["1", "2"].contains(twice.sessions.value))
        print("TodayOrderAdversarialTests one id twice: \(shown[0]) | reversed: \(shown[1]) | the same copy twice: "
            + "\(twice.sessions.value) session(s), \(twice.volume.value)k")
    }
}
