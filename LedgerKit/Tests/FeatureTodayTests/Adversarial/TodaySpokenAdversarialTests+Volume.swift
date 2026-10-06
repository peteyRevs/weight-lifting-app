@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2, criterion 14: the volume tile's spoken line names the week and what the change is against, "24,180
/// lb moved this week, +8% from last week" and "24,180 lb moved this week", kilograms alike.
nonisolated extension TodaySpokenAdversarialTests {
    /// This week's and last week's pounds, and the whole line in pounds and in kilograms.
    struct Line: Sendable, CustomStringConvertible {
        let this: Decimal
        let previous: Decimal?
        let pounds: String
        let kilograms: String

        init(_ this: Decimal, _ previous: Decimal?, _ pounds: String, _ kilograms: String) {
            self.this = this
            self.previous = previous
            self.pounds = pounds
            self.kilograms = kilograms
        }

        var description: String {
            pounds
        }
    }

    /// 24,180 lb = 10,967.9 kg; 21,728 lb = 9,855.7 kg; 22,400 lb = 10,160.5 kg; 20,100 lb = 9,117.2 kg.
    static let lines = [
        Line(
            24180,
            22400,
            "24,180 lb moved this week, +8% from last week",
            "10,968 kg moved this week, +8% from last week"
        ),
        Line(
            21728,
            22400,
            "21,728 lb moved this week, −3% from last week",
            "9,856 kg moved this week, −3% from last week"
        ),
        Line(
            22400,
            22400,
            "22,400 lb moved this week, 0% from last week",
            "10,160 kg moved this week, 0% from last week"
        ),
        Line(24180, nil, "24,180 lb moved this week", "10,968 kg moved this week"),
        Line(24180, 0, "24,180 lb moved this week", "10,968 kg moved this week"),
        Line(
            20100,
            20000,
            "20,100 lb moved this week, +1% from last week",
            "9,117 kg moved this week, +1% from last week"
        ),
        Line(0, 20000, "0 lb moved this week, −100% from last week", "0 kg moved this week, −100% from last week"),
        Line(0, nil, "0 lb moved this week", "0 kg moved this week")
    ]

    @Test("The volume tile's spoken line is the ruling's, in pounds and in kilograms", arguments: lines)
    func volumeLine_isTheRulings(_ row: Line) throws {
        let start = try Support.moment(Support.civil(2026, 9, 15), 7)
        let workout = try Support.lifted(
            number: 530,
            start: start,
            lifts: [Support.Lift(weight: .pounds(row.this), reps: 1)]
        )
        for units in Units.allCases {
            let input = try Support.input(
                Support.seed(),
                now: Self.wednesday(),
                settings: Support.settings(units),
                week: [workout],
                previous: row.previous.map { Volume(weight: .pounds($0), reps: .one) }
            )
            let tile = TodayPresentation.make(input).stats.volume
            #expect(tile.accessibilitySummary == (units == .lb ? row.pounds : row.kilograms))
            // What is drawn has not moved: the caption and the change stay two short texts.
            #expect(tile.caption == (units == .lb ? "lb moved" : "kg moved"))
            #expect(tile.delta.map { row.pounds.contains(", \($0) from last week") } ?? !row.pounds.contains("from"))
        }
    }

    @Test("The line's minus is the real one, and the Logged card's sentence keeps its own words")
    func volumeLine_keepsTheMinusAndLeavesTheCardAlone() throws {
        let program = try Support.seed()
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let done = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 531, start: start),
            after: 1462
        )
        let previous = Volume(weight: .pounds(40000), reps: .one)
        let model = try TodayPresentation.make(Support.input(
            program,
            now: Self.wednesday(),
            week: [done],
            previous: previous
        ))
        // 30,370 lb after 40,000 lb is −24.1 %.
        #expect(model.stats.volume.accessibilitySummary == "30,370 lb moved this week, \u{2212}24% from last week")
        #expect(try Support.logged(model).stats == "15 of 15 sets · 30,370 lb moved")
    }
}
