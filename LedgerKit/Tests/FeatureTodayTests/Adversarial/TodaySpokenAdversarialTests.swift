@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: what VoiceOver reads (S3 criteria 2, 8 and 10): the strip's cells and the two tiles. Each
/// spoken text is present, says what is drawn, and is English copy with the numbers the tile shows.
@Suite("Adversarial F09 S3 · spoken texts", .tags(.feature))
nonisolated struct TodaySpokenAdversarialTests {
    typealias Support = TodayAdversarial

    static func wednesday() throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16), 20)
    }

    @Test("Each cell of the strip speaks its whole date; today's says it is today once its mark says Done")
    func stripCells_speakTheirDate() throws {
        let program = try Support.seed()
        let plain = try TodayPresentation.make(Support.input(program, now: Self.wednesday()))
        let dates = (14 ... 20).map { "\(Support.weekdays[$0 - 14]), September \($0)" }
        #expect(plain.weekStrip.map(\.accessibilitySummary) == dates)
        #expect(plain.weekStrip[2].accessibilitySummary == plain.header.date)
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let done = try Support.lifted(number: 500, start: start, lifts: [.pounds(100, 10)])
        let trained = try TodayPresentation.make(Support.input(program, now: Self.wednesday(), week: [done]))
        #expect(trained.weekStrip[2].mark == .done)
        #expect(trained.weekStrip[2].accessibilitySummary == "Today, Wednesday, September 16")
        var others = trained.weekStrip.map(\.accessibilitySummary)
        others.remove(at: 2)
        #expect(others == Array(dates[..<2] + dates[3...]))
    }

    @Test("The sessions tile speaks done of planned, in the singular for one planned", arguments: [
        [0, 0], [0, 1], [1, 1], [2, 1], [1, 2], [5, 4]
    ])
    func sessionsTile_speaksDoneOfPlanned(_ counts: [Int]) throws {
        var program = try Support.seed()
        let weekdays: [Weekday] = [.monday, .friday, .saturday, .sunday]
        program.weeks[0].schedule = Dictionary(
            uniqueKeysWithValues: zip(weekdays.prefix(counts[1]), program.days.map(\.id))
        )
        let workouts = try (0 ..< counts[0]).map { index in
            let start = try Support.moment(Support.civil(2026, 9, 14 + index % 2), 6 + index)
            return try Support.lifted(number: 510 + index, start: start, lifts: [.pounds(100, 10)])
        }
        let model = try TodayPresentation.make(Support.input(program, now: Self.wednesday(), week: workouts))
        let noun = counts[1] == 1 ? "session" : "sessions"
        #expect(model.stats.sessions.accessibilitySummary == "\(counts[0]) of \(counts[1]) \(noun) this week")
        #expect(model.stats.sessions.value == String(counts[0]))
        #expect(model.stats.sessions.unit == "/\(counts[1])")
    }

    /// This week's pounds, last week's, and the units: what the volume tile says aloud.
    struct Spoken: Sendable, CustomStringConvertible {
        let this: Decimal
        let previous: Decimal?
        let units: Units
        let whole: String

        init(_ this: Decimal, _ previous: Decimal?, _ units: Units, _ whole: String) {
            self.this = this
            self.previous = previous
            self.units = units
            self.whole = whole
        }

        var description: String {
            "\(this) lb after \(previous.map { "\($0)" } ?? "nothing") in \(units)"
        }
    }

    static let spoken = [
        Spoken(24180, 22400, .lb, "24,180 lb moved"),
        Spoken(24180, 22400, .kg, "10,968 kg moved"),
        Spoken(21728, 22400, .lb, "21,728 lb moved"),
        Spoken(22400, 22400, .lb, "22,400 lb moved"),
        Spoken(24180, nil, .lb, "24,180 lb moved"),
        Spoken(0, 22400, .kg, "0 kg moved"),
        Spoken(0, nil, .lb, "0 lb moved")
    ]

    @Test("The volume tile speaks the whole number it rounds, its unit, and the change it draws", arguments: spoken)
    func volumeTile_speaksTheWholeNumberAndTheChange(_ row: Spoken) throws {
        let start = try Support.moment(Support.civil(2026, 9, 15), 7)
        let workout = try Support.lifted(
            number: 520,
            start: start,
            lifts: [Support.Lift(weight: .pounds(row.this), reps: 1)]
        )
        let input = try Support.input(
            Support.seed(),
            now: Self.wednesday(),
            settings: Support.settings(row.units),
            week: [workout],
            previous: row.previous.map { Volume(weight: .pounds($0), reps: .one) }
        )
        let tile = TodayPresentation.make(input).stats.volume
        let said = tile.accessibilitySummary
        #expect(said.hasPrefix(row.whole), "\(said)")
        if let delta = tile.delta {
            #expect(said.hasSuffix(delta), "\(said) against the drawn \(delta)")
            #expect(said.count > row.whole.count + delta.count)
        } else {
            #expect(said == row.whole)
        }
        print("TodaySpokenAdversarialTests volume tile, \(row): \"\(said)\"")
    }
}
