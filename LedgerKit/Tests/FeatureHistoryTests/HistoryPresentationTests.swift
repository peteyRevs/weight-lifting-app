@testable import FeatureHistory
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1, criteria 1, 2 and 7 (the list's part) and N7's words, through the pure presentation: the weeks and their
/// headers, each row's meta and badge, the units, the spoken row, and the empty list.
@Suite("HistoryPresentation", .tags(.feature))
struct HistoryPresentationTests {
    static let twelve = HistoryFixtures.entries(HistoryFixtures.twelve())

    @Test("1. Twelve workouts over four weeks: four weeks newest first, three rows each, newest first")
    func twelveWorkouts_fourWeeksNewestFirst() {
        let model = HistoryPresentation.make(HistoryFixtures.input(Self.twelve))
        #expect(model.title == "History")
        #expect(model.weeks.map(\.title) == ["Sep 7 – 13", "Aug 31 – Sep 6", "Aug 24 – 30", "Aug 17 – 23"]
            .map(\.thinSpaced))
        #expect(model.weeks.map(\.id) == [
            Fixtures.date(2026, 9, 7), Fixtures.date(2026, 8, 31), Fixtures.date(2026, 8, 24),
            Fixtures.date(2026, 8, 17)
        ])
        let names = model.weeks.map { $0.rows.map(\.name) } == Array(
            repeating: ["Upper B", "Lower A", "Upper A"],
            count: 4
        )
        #expect(names)
        let inTheRepositorysOrder = model.rows.map(\.id) == Self.twelve.map(\.id)
        #expect(inTheRepositorysOrder)
        let routes = model.rows.map(\.route) == Self.twelve.map { .workout($0.id) }
        #expect(routes)
    }

    @Test("1. A row reads its weekday, its whole minutes and its volume: Wed · 58 min · 24,180 lb")
    func row_readsWeekdayMinutesAndVolume() throws {
        // 26 sets of 5 at 186 lb: 24,180 lb, on Wednesday 2026-09-09, 58 minutes and 59 seconds long.
        var workout = HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 9, hour: 7), sets: 26, pounds: 186)
        workout.endedAt = workout.startedAt.addingTimeInterval(58 * 60 + 59)
        let model = HistoryPresentation.make(HistoryFixtures.input([HistoryEntry(workout, prCount: 1)]))
        let row = try #require(model.rows.first)
        #expect(row.name == "Upper A")
        #expect(row.meta == "Wed · 58 min · 24,180 lb")
        #expect(row.badge == "1 PR")
        #expect(row.spokenValue == "Wednesday, 58 minutes, 24,180 pounds, 1 PR")
    }

    @Test("1. The badge counts the records: none with no badge, 1 PR, 3 PRs")
    func badge_countsTheRecords() {
        let start = Fixtures.date(2026, 9, 9, hour: 7)
        let entries = [0, 1, 3].enumerated().map { place, count in
            HistoryEntry(
                HistoryFixtures.workout(place, startedAt: start.addingTimeInterval(-3600 * Double(place))),
                prCount: count
            )
        }
        let rows = HistoryPresentation.make(HistoryFixtures.input(entries)).rows
        #expect(rows.map(\.badge) == [nil, "1 PR", "3 PRs"])
        #expect(rows.first?.spokenValue == "Wednesday, 58 minutes, 2,775 pounds", "no record is read as none")
        #expect(rows.last?.spokenValue.hasSuffix(", 3 PRs") == true)
    }

    @Test("7. In kilograms each volume is converted, and spoken in kilograms")
    func kilograms_convertTheVolumes() throws {
        let workout = HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 9, hour: 7), sets: 26, pounds: 186)
        let model = HistoryPresentation.make(HistoryFixtures.input([HistoryEntry(workout, prCount: 0)], units: .kg))
        let row = try #require(model.rows.first)
        #expect(row.meta == "Wed · 58 min · 10,968 kg")
        #expect(row.spokenValue == "Wednesday, 58 minutes, 10,968 kilograms")
    }

    @Test("A week across two months names both; a week in another year names its years")
    func headers_acrossAMonthAndAYear() {
        let entries = [
            HistoryEntry(HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 1, hour: 7)), prCount: 0),
            HistoryEntry(HistoryFixtures.workout(2, startedAt: Fixtures.date(2026, 1, 1, hour: 7)), prCount: 0),
            HistoryEntry(HistoryFixtures.workout(3, startedAt: Fixtures.date(2025, 9, 10, hour: 7)), prCount: 0)
        ]
        let titles = HistoryPresentation.make(HistoryFixtures.input(entries)).weeks.map(\.title)
        #expect(titles == ["Aug 31 – Sep 6", "Dec 29, 2025 – Jan 4, 2026", "Sep 8 – 14, 2025"].map(\.thinSpaced))
    }

    @Test("The weeks begin on the lifter's first day: a Sunday start moves Sunday's workout into the next week")
    func weekStart_sunday_regroups() {
        let sunday = HistoryEntry(
            HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 13, hour: 7)),
            prCount: 0
        )
        let saturday = HistoryEntry(
            HistoryFixtures.workout(2, startedAt: Fixtures.date(2026, 9, 12, hour: 7)),
            prCount: 0
        )
        let monday = HistoryPresentation.make(HistoryFixtures.input([sunday, saturday]))
        let sundays = HistoryPresentation.make(HistoryFixtures.input([sunday, saturday], weekStart: .sunday))
        #expect(monday.weeks.map(\.title) == ["Sep 7 – 13"].map(\.thinSpaced))
        #expect(sundays.weeks.map(\.title) == ["Sep 13 – 19", "Sep 6 – 12"].map(\.thinSpaced))
    }

    @Test("2. No workout: the empty state, whose one button goes to Today")
    func noWorkouts_isTheEmptyState() {
        let model = HistoryPresentation.make(HistoryFixtures.input([]))
        #expect(model.weeks.isEmpty)
        #expect(model.content == .empty(HistoryModel.Empty(
            title: "No workouts yet.",
            body: "Finish a workout and it shows up here.",
            actionTitle: "Go to Today",
            route: .today
        )))
    }

    @Test("N7. Units are spoken plural-correct: a one-pound workout reads 1 pound, never 1 pounds")
    func spokenVolume_isPluralCorrect() throws {
        var workout = HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 9, hour: 7), sets: 1, pounds: 1)
        workout.exercises[0].sets[0].reps = Reps(clamping: 1)
        workout.endedAt = workout.startedAt.addingTimeInterval(60)
        let row = try #require(HistoryPresentation.make(HistoryFixtures.input([HistoryEntry(workout, prCount: 0)])).rows
            .first)
        #expect(row.meta == "Wed · 1 min · 1 lb")
        #expect(row.spokenValue == "Wednesday, 1 minute, 1 pound")
    }

    @Test("F13-S1-1. Outside English the spoken volume is in the catalog's language, with the region's digits")
    func spokenVolume_inGerman_speaksTheCatalogsLanguage() throws {
        let workout = HistoryFixtures.workout(1, startedAt: Fixtures.date(2026, 9, 9, hour: 7), sets: 26, pounds: 186)
        var input = HistoryFixtures.input([HistoryEntry(workout, prCount: 0)])
        input.locale = Locale(identifier: "de_DE")
        let row = try #require(HistoryPresentation.make(input).rows.first)
        #expect(row.spokenValue.hasSuffix(", 58 minutes, 24.180 pounds"), "\(row.spokenValue)")
    }
}
