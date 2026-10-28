@testable import FeatureHistory
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1 adversarial (G2): the History list's words at their edges. A workout's length at 0 s, 59 s, a minute and
/// ten hours; volumes of 0, 1 lb and over 450,000 kg; badges of 0, 1 and 2; every first day of the week across a
/// year end; a workout begun late on a week's last day in a zone with daylight saving; and the row's words in
/// de_DE, ja_JP and ar_EG. Tests that fail on the branch as built are wrapped in `withKnownIssue` and name their
/// finding (`tasks/features/F13-workout-history/test-findings.md`).
@Suite("Adversarial F13 S1 · the History list's words", .tags(.feature))
struct HistoryRowAdversarialTests {
    /// An entry started at `startedAt`, `seconds` long, moving `volume`, holding `records` records.
    static func entry(
        _ number: Int,
        _ startedAt: Date = Fixtures.date(2026, 9, 16, hour: 7),
        seconds: Int64 = 3480,
        volume: Volume = Volume(weight: .pounds(186), reps: Reps(clamping: 130)),
        records: Int = 1
    ) -> HistoryEntry {
        HistoryEntry(
            id: WorkoutID(Fixtures.uuid(9100 + number)),
            name: "Upper A",
            tag: "UA",
            isDeload: false,
            startedAt: startedAt,
            elapsed: .seconds(seconds),
            volume: volume,
            doneSets: 1,
            totalSets: 1,
            prCount: records
        )
    }

    /// The one row of `entry`, in `units` and `locale`.
    static func row(
        _ entry: HistoryEntry,
        units: Units = .lb,
        locale: Locale = Fixtures.locale
    ) throws -> HistoryModel.Row {
        var input = HistoryFixtures.input([entry], units: units)
        input.locale = locale
        return try #require(HistoryPresentation.make(input).rows.first)
    }

    // MARK: - Counted words

    @Test("Plurals: a minute is \"1 min\", spoken \"1 minute\"; 1 lb moved is \"1 pound\"; 1 PR, 2 PRs, no badge at 0")
    func plurals_takeTheirNumbersForm() throws {
        let minute = try Self.row(Self.entry(
            1,
            seconds: 119,
            volume: Volume(weight: .pounds(1), reps: Reps(clamping: 1))
        ))
        #expect(minute.meta == "Wed · 1 min · 1 lb")
        #expect(minute.spokenValue == "Wednesday, 1 minute, 1 pound, 1 PR")
        #expect(minute.badge == "1 PR")
        #expect(try Self.row(Self.entry(2, records: 2)).badge == "2 PRs")
        let none = try Self.row(Self.entry(3, volume: .zero, records: 0))
        #expect(none.badge == nil)
        #expect(none.spokenValue == "Wednesday, 58 minutes, 0 pounds", "no badge, no trailing separator")
    }

    @Test("Ten hours and a very large volume in kilograms: whole minutes and whole kilograms, nothing clipped")
    func longAndHeavy_readsWholeNumbers() throws {
        let heavy = Volume(weight: .pounds(1000), reps: Reps(clamping: 999))
        let row = try Self.row(Self.entry(1, seconds: 36001, volume: heavy), units: .kg)
        #expect(row.meta == "Wed · 600 min · 453,139 kg")
        #expect(row.spokenValue == "Wednesday, 600 minutes, 453,139 kilograms, 1 PR")
    }

    /// F13-S1-2: a workout shorter than a minute (a quick test save, the nightly UI test's own sample workout, or one
    /// whose end a clock moved before its start) read "0 min", "0 minutes". Fixed in fix round 1 (orchestrator's
    /// ruling): it reads "<1 min", spoken "under a minute"; a minute reads "1 min" again.
    @Test("F13-S1-2. A workout of 59 s, or of 0 s, does not read \"0 min\"")
    func underAMinute_doesNotReadZero() throws {
        let short = try Self.row(Self.entry(1, seconds: 59))
        let none = try Self.row(Self.entry(2, seconds: 0))
        let minute = try Self.row(Self.entry(3, seconds: 60))
        #expect(!short.meta.contains(" 0 min"), "\(short.meta)")
        #expect(!none.meta.contains(" 0 min"), "\(none.meta)")
        #expect(!short.spokenValue.contains("0 minutes"), "\(short.spokenValue)")
        #expect(short.meta == "Wed · <1 min · 24,180 lb")
        #expect(none.spokenValue == "Wednesday, under a minute, 24,180 pounds, 1 PR")
        #expect(minute.meta == "Wed · 1 min · 24,180 lb")
    }

    // MARK: - Weeks

    @Test(
        "Every first day of the week names the year on both sides of a week across 2025 and 2026",
        arguments: [
            (Weekday.monday, "Dec 29, 2025 – Jan 4, 2026"),
            (.tuesday, "Dec 30, 2025 – Jan 5, 2026"),
            (.wednesday, "Dec 31, 2025 – Jan 6, 2026"),
            (.thursday, "Jan 1 – 7"),
            (.friday, "Dec 26, 2025 – Jan 1, 2026"),
            (.saturday, "Dec 27, 2025 – Jan 2, 2026"),
            (.sunday, "Dec 28, 2025 – Jan 3, 2026")
        ]
    )
    func yearEnd_everyWeekStart(weekStart: Weekday, title: String) {
        // New Year's Day 2026, a Thursday, seen from September 2026.
        let input = HistoryFixtures.input([Self.entry(1, Fixtures.date(2026, 1, 1, hour: 7))], weekStart: weekStart)
        #expect(HistoryPresentation.make(input).weeks.map(\.title) == [title.thinSpaced])
    }

    @Test("Seen from the next year, a week wholly in the year before names its year once")
    func lastYearsWeek_namesItsYear() {
        let input = HistoryFixtures.input(
            [Self.entry(1, Fixtures.date(2026, 9, 16, hour: 7))],
            now: Fixtures.date(2027, 1, 2, hour: 9)
        )
        #expect(HistoryPresentation.make(input).weeks.map(\.title) == ["Sep 14 – 20, 2026".thinSpaced])
    }

    @Test("Begun at 23:30 on the Sunday daylight saving ends in New York, a workout stays in that Monday week")
    func lateOnTheLastDay_acrossDaylightSaving_staysInItsWeek() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let late = Self.entry(1, Fixtures.date(2026, 11, 1, hour: 23, minute: 30, in: newYork), seconds: 5400)
        let next = Self.entry(2, Fixtures.date(2026, 11, 2, hour: 0, minute: 30, in: newYork))
        var input = HistoryFixtures.input([next, late])
        input.calendar = calendar
        let model = HistoryPresentation.make(input)
        #expect(model.weeks.map(\.title) == ["Nov 2 – 8", "Oct 26 – Nov 1"].map(\.thinSpaced))
        #expect(model.weeks.map { $0.rows.map(\.id) } == [[next.id], [late.id]])
        #expect(model.weeks.last?.rows.first?.meta.hasPrefix("Sun · 90 min") == true)
    }

    // MARK: - Locales

    /// F13-S1-1: A6's spoken weight takes its unit word from Foundation in the lifter's locale, where every other word
    /// of the row comes from the module's catalog in the language it answers in (`forCountedText`), English. So one
    /// VoiceOver phrase mixed languages: "Mittwoch, 58 minutes, 24.180 Pfund, 1 PR". Fixed in fix round 1
    /// (orchestrator's ruling): the unit's word is in the catalog's language, with the locale's region and digits.
    @Test("F13-S1-1. Outside English, the row's spoken unit is in the language of its other words", arguments: [
        "de_DE", "ja_JP", "ar_EG", "fr_FR"
    ])
    func spokenValue_speaksOneLanguage(identifier: String) throws {
        let row = try Self.row(Self.entry(1), locale: Locale(identifier: identifier))
        #expect(row.spokenValue.contains("minutes"), "the catalog's English: \(row.spokenValue)")
        #expect(row.spokenValue.contains("pounds"), "\(row.spokenValue)")
    }

    /// F13-S1-3: the drawn meta takes its minutes and badge in the locale's digits (`forCountedText` keeps the
    /// numbering system) and its volume in ASCII digits (the Domain's `Volume.formatted(in:)`), so an ar_EG row reads
    /// "أربعاء · ٥٨ min · 24,180 lb" beside a "١ PR" badge. Today's RECENT row has the same mix (pre-existing).
    @Test("F13-S1-3. In ar_EG the drawn row writes every number in one numbering system")
    func arabic_drawnRow_usesOneNumberingSystem() throws {
        let row = try Self.row(Self.entry(1), locale: Locale(identifier: "ar_EG"))
        let text = row.meta + " " + (row.badge ?? "")
        let ascii = text.unicodeScalars.contains { ("0" ... "9").contains($0) }
        let arabic = text.unicodeScalars.contains { ("\u{660}" ... "\u{669}").contains($0) }
        #expect(arabic, "the minutes and the badge follow the locale: \(text)")
        // Left as built (orchestrator's ruling): an app-wide pattern Today's RECENT shares. Follow-up: "one numbering
        // system per row (app-wide localisation chore)".
        withKnownIssue("F13-S1-3: the volume is written in ASCII digits beside Arabic-Indic ones") {
            #expect(!ascii, "\(text)")
        }
    }
}
