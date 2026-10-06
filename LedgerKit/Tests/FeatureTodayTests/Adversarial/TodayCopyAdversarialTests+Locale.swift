@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The injected locale groups the digits of the catalog's numbers; the words stay the catalog's, and what the
/// Domain formats (loads, volumes, clocks) does not move. Nothing drawn or spoken holds a placeholder.
nonisolated extension TodayCopyAdversarialTests {
    /// The seed's schedule for 1,200 weeks: numbers large enough to be grouped.
    static func longBlock() throws -> Program {
        let seed = try Support.seed()
        let weeks = (0 ..< 1200).map { index in
            Week(id: WeekID(Fixtures.uuid(50000 + index)), index: index, schedule: seed.weeks[0].schedule)
        }
        return try Program(id: seed.id, name: seed.name, startDate: seed.startDate, weeks: weeks, days: seed.days)
    }

    static let locales = ["en_US", "en_DE", "en_CH", "en_IN", "en_ZA", "en_SE"]

    /// The models of four days of week 1,000 and of the day after the block, in `locale`.
    static func models(_ program: Program, _ locale: Locale) throws -> [TodayModel] {
        let monday = try #require(program.startDate.adding(days: 999 * 7))
        let saturday = try Support.moment(#require(monday.adding(days: 5)), 6)
        let logged = try Support.finished(Support.live(program, week: 999, tag: "LB", number: 700, start: saturday))
        let long = try Support.lifted(
            number: 701,
            start: saturday.addingTimeInterval(-7 * 86400),
            seconds: 6_000_000,
            lifts: [.pounds(100, 10)]
        )
        let many = try (0 ..< 1500).map { index in
            try Support.lifted(number: 1000 + index, start: saturday.addingTimeInterval(TimeInterval(index)), lifts: [])
        }
        let after = try #require(program.startDate.adding(days: 1200 * 7))
        var inputs = try [
            Support.input(program, now: Support.moment(#require(monday.adding(days: 2)))),
            Support.input(program, now: saturday.addingTimeInterval(7200), week: [logged], recent: [logged, long]),
            Support.input(program, now: Support.moment(#require(monday.adding(days: 6))), week: many),
            Support.input(program, now: Support.moment(after), previous: Volume(weight: .pounds(1), reps: .one))
        ]
        for index in inputs.indices {
            inputs[index].locale = locale
        }
        return inputs.map(TodayPresentation.make)
    }

    @Test("The locale groups the digits of weeks, sessions and minutes", arguments: locales)
    func locale_groupsTheDigits(_ identifier: String) throws {
        let locale = Locale(identifier: identifier)
        let models = try Self.models(Self.longBlock(), locale)
        let thousand = 1000.formatted(.number.locale(locale))
        let block = 1200.formatted(.number.locale(locale))
        #expect(try Support.upNext(models[0]).meta == "Week \(thousand) of \(block) · ~38 min")
        let logged = try Support.logged(models[1])
        #expect(logged.eyebrow == "LOGGED · WEEK \(thousand)")
        #expect(logged.next == "Next: week \(1001.formatted(.number.locale(locale)))")
        let minutes = 100_000.formatted(.number.locale(locale))
        #expect(models[1].recent.rows.last?.meta.contains(" · \(minutes) min · 1,000 lb") == true)
        let rest = try Support.rest(models[2])
        #expect(rest.body == "Nothing scheduled for Sunday in week \(thousand). Next up is next Monday.")
        #expect(rest.offSchedule.subtitle == "Pick a day from week \(thousand).")
        let sessions = 1500.formatted(.number.locale(locale))
        #expect(models[2].stats.sessions.value == sessions)
        #expect(models[2].stats.sessions.unit == "/4")
        #expect(models[2].stats.sessions.accessibilitySummary == "\(sessions) of 4 sessions this week")
        #expect(try Support.blockComplete(models[3]).body == "\(block) weeks done. Start the next block from Program.")
    }

    /// A model's texts apart from its dates (the header's date and the strip's spoken dates follow the locale's
    /// own order of day and month), with every separator between two digits taken out.
    static func words(_ model: TodayModel) -> [String] {
        let texts = Support.texts(in: model.card) + Support.texts(in: model.stats) + Support.texts(in: model.recent)
            + [model.header.title, model.header.settings.title] + model.weekStrip.flatMap { [$0.weekday, $0.date] }
        let separator = #"(?<=\d)[,.’'\x{00A0}\x{202F} ](?=\d)"#
        return texts.map { $0.replacingOccurrences(of: separator, with: "", options: .regularExpression) }
    }

    @Test(
        "Apart from the grouping of digits and the dates, every text is the same in every English locale",
        arguments: locales
    )
    func locale_changesNothingButTheGrouping(_ identifier: String) throws {
        let program = try Self.longBlock()
        let reference = try Self.models(program, Support.english)
        let models = try Self.models(program, Locale(identifier: identifier))
        var lines: [String] = []
        for (model, expected) in zip(models, reference) {
            let pairs = zip(Self.words(model), Self.words(expected)).filter { $0 != $1 }
            lines += pairs.prefix(3).map { "\"\($0)\" in \(identifier), \"\($1)\" in en_US" }
            if Self.words(model).count != Self.words(expected).count {
                lines.append("\(Self.words(model).count) texts against \(Self.words(expected).count)")
            }
        }
        let agrees = lines.isEmpty
        #expect(agrees, "\(lines.count) texts differ:\n\(lines.prefix(5).joined(separator: "\n"))")
        let volume = try Support.logged(models[1]).stats
        #expect(try volume == (Support.logged(reference[1]).stats))
    }

    @Test("Nothing drawn or spoken is empty, holds a placeholder or names the product", arguments: [
        UInt64(0) ... 999
    ])
    func everyText_isFinished(_ seeds: ClosedRange<UInt64>) throws {
        let catalog = try Support.exercises()
        let marks = ["%@", "%lld", "%%", "$@", "Optional(", "nil", "  ", "ledger", "\n"]
        var lines: [String] = []
        var count = 0
        for seed in seeds {
            let scenario = try TodayScenario(seed: seed, catalog: catalog)
            for text in Support.texts(in: TodayPresentation.make(scenario.input)) {
                count += 1
                let lowered = text.lowercased()
                let isTrimmed = !text.isEmpty && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
                let dots = text.split(separator: "·", omittingEmptySubsequences: false)
                let endsInSpace = dots.dropLast().allSatisfy { $0.hasSuffix(" ") }
                let startsWithSpace = dots.dropFirst().allSatisfy { $0.hasPrefix(" ") }
                let isMarked = marks.contains { lowered.contains($0.lowercased()) }
                if !isTrimmed || !endsInSpace || !startsWithSpace || isMarked {
                    lines.append("seed \(seed): \"\(text)\"")
                }
            }
        }
        let isClean = lines.isEmpty
        #expect(isClean, "\(lines.count) of \(count) texts:\n\(lines.prefix(6).joined(separator: "\n"))")
        print("TodayCopyAdversarialTests looked at \(count) texts of \(seeds.count) seeded models")
    }
}
