@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: the words (criteria 7 and 8) and the module's sources (criteria 7 and 9), read
/// by the tester's own scans. Every text a screen draws or speaks must be one the brief's "Copy (exact)"
/// writes, a text the brief does not give that the tester lists in the findings, a weekday's letter or name,
/// or data.
@Suite("Adversarial F11 S5 · the words and the sources", .tags(.feature))
nonisolated struct ProgramWordsAdversarialTests {
    /// The brief's texts, as patterns over a whole line.
    static let brief = [
        "MY PROGRAM", "Program name", #"BLOCK · \d+ WEEKS"#, #"W\d+"#, #"\d+ DAYS?"#, "DELOAD", #"WEEK \d+"#,
        #"WEEK \d+ · DELOAD"#, "Tap to assign", "REST", "First week", #"Copy week \d+"#, "Apply to later weeks",
        "Deload", "TRAINING DAYS", #"\d+ days? · \d+ sets? a week"#,
        "Shared by every week\\. The schedule above decides which day you train, and when\\.",
        #"\d+ exercises? · \d+ sets? · ~\d+ min"#, "No exercises yet", #"\+\d+"#, #"\+ Add training day"#,
        "A block needs at least 2 weeks\\.", #"Week \d+ has logged sessions and can't be removed\."#,
        "Add at least one exercise before scheduling this day\\."
    ]

    /// The texts the brief does not give: all of them spoken, but the dash.
    static let notGiven = [
        "Block length",
        #"\d+ weeks"#,
        #"Week \d+"#,
        #"\d+ days?"#,
        "Rest",
        "Double-tap to assign",
        "—"
    ]

    /// Every text of a model, with where it stands.
    static func texts(of model: ProgramBuilderModel) -> [(place: String, text: String)] {
        var all: [(String, String)] = [
            ("eyebrow", model.header.eyebrow), ("name", model.header.name),
            ("placeholder", model.header.namePlaceholder), ("block", model.block.title),
            ("block spoken", model.block.spokenLabel), ("block spoken", model.block.spokenValue),
            ("week", model.week.title), ("hint", model.week.hint ?? "REST"), ("copy", model.week.copyPrevious.title),
            ("apply", model.week.applyToLater?.title ?? "REST"), ("deload", model.week.deload.title),
            ("days", model.days.title), ("summary", model.days.summary), ("helper", model.days.helper),
            ("add day", model.days.addDay.title), ("notice", model.notice ?? "REST")
        ]
        for chip in model.block.chips {
            all += [chip.title, chip.subtitle, chip.spokenLabel, chip.spokenValue].map { ("chip", $0) }
        }
        for cell in model.week.cells {
            all += [cell.letter, cell.label, cell.spokenLabel, cell.spokenValue].map { ("cell", $0) }
            all += [cell.spokenHint].compactMap(\.self).map { ("cell", $0) }
        }
        for card in model.days.cards {
            all += ([card.tag, card.name, card.meta, card.spokenLabel, card.spokenValue] + card.chips)
                .map { ("card", $0) }
        }
        return all
    }

    static func matches(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.range(of: "^(?:\($0))$", options: .regularExpression) != nil }
    }

    @Test(
        "Every text of the seed's screens is the brief's, a listed spoken text, a weekday's or data",
        arguments: 0 ..< 8
    )
    func everyText_isTheBriefsOrListedOrData(week: Int) throws {
        var input = try AdvProgram.seed(week: week)
        input.program = ProgramEditing.addDay(input.program, id: DayTemplateID(Fixtures.uuid(88)), name: "New day")
        input.program = ProgramEditing.cycleSchedule(input.program, week: week, weekday: .sunday)
        input.exercises[Fixtures.CatalogID.benchPress] = nil
        input
            .notice = [
                .minimumTwoWeeks,
                .weekHasLoggedSessions(weekNumber: week + 1),
                .dayHasNoExercises,
                nil
            ][week % 4]
        let english = ProgramWeekdaysAdversarialTests.languages[0]
        let data = Set(
            [input.program.name] + input.program.days.flatMap { [$0.name, $0.tag, $0.shortTitle] }
                + input.exercises.values.map(\.shortName) + english.letters + english.names
        )
        let strangers = Self.texts(of: ProgramPresentation.make(input)).filter { entry in
            !data.contains(entry.text) && !Self.matches(entry.text, Self.brief) && !Self.matches(
                entry.text,
                Self.notGiven
            )
        }
        #expect(strangers.isEmpty, "\(strangers.prefix(4))")
    }

    @Test(
        "An entry for a day the program no longer holds reads REST, is not counted, and a tap assigns the first day"
    )
    func entryOfADayNotHeld_readsRest() throws {
        var input = try AdvProgram.seed()
        input.program.days.removeFirst()
        let model = ProgramPresentation.make(input)
        #expect(model.week.cells.map(\.label) == ["REST", "REST", "LA", "REST", "UB", "LB", "REST"])
        #expect(model.block.chips.map(\.subtitle) == Array(repeating: "3 DAYS", count: 7) + ["DELOAD"])
        #expect(model.week.cells.first?.spokenValue == "Rest")
        let after = try ProgramPresentation.make(AdvStore.apply(
            #require(model.week.cells[0].action),
            to: input,
            fresh: 1
        ).input)
        #expect(after.week.cells.first?.label == "LA")
    }
}

nonisolated extension ProgramWordsAdversarialTests {
    // MARK: The sources

    static func sources() throws -> [(name: String, text: String)] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FeatureProgram")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }.map {
            try ($0.lastPathComponent, String(contentsOf: $0, encoding: .utf8))
        }
    }

    /// The file's code: every line without its comment.
    static func code(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
        }
    }

    @Test("No source of the module reads the clock, the device's calendar, locale or time zone, or draws at random")
    func sources_readNothingAmbient() throws {
        let banned = [
            "Date()", "Date.now", ".now", "Calendar.current", "Locale.current", "TimeZone.current",
            "autoupdatingCurrent", "Calendar.autoupdating", "Locale.autoupdating", "UUID()", ".random",
            "ProcessInfo", "UserDefaults", "Locale.preferredLanguages", "NSLocale", "Date(timeIntervalSinceNow",
            "locale: .current", "CFAbsoluteTimeGetCurrent", "DispatchTime", "ContinuousClock", "SystemRandom"
        ]
        var found: [String] = []
        let files = try Self.sources()
        for file in files {
            for (number, line) in Self.code(file.text).enumerated() {
                found += banned.filter { line.contains($0) }.map { "\(file.name):\(number + 1) \($0)" }
            }
        }
        #expect(files.count >= 9, "the scan found \(files.map(\.name))")
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Outside the copy files the only literals are the empty one and the separator, and no lookup is made")
    func sources_holdNoCopyOutsideTheCopyFiles() throws {
        var found: [String] = []
        for file in try Self.sources() where !file.name.hasPrefix("ProgramCopy") {
            // Every literal, read by `SwiftSource`, but a log line's message (the first unlabelled argument of
            // `logger.log.<level>`) and the logger's category `"program"`: they are for the developer, never
            // read or heard by a lifter (standards §8; F11 S13 fix round 1, the round 1 tester's rule).
            let source = SwiftSource(file.text)
            let isForTheDeveloper = ProgramStoreSourceAdversarialTests.isForTheDeveloper
            found += source.literals
                .filter { !["", " · "].contains($0.text) && !isForTheDeveloper($0, source) }
                .map { "\(file.name):\($0.line) \"\($0.text)\"" }
            for (number, line) in Self.code(file.text).enumerated() {
                let lookups = ["String(localized", "LocalizedStringKey", "NSLocalizedString", "Text(", "bundle:"]
                found += lookups.filter { line.contains($0) }.map { "\(file.name):\(number + 1) \($0)" }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Every lookup of the copy files names the module's bundle, and one with a value names the locale")
    func copyFiles_everyValueCarriesTheLocale() throws {
        var found: [String] = []
        var lookups = 0
        for file in try Self.sources() where file.name.hasPrefix("ProgramCopy") {
            let statements = file.text.components(separatedBy: "localized:").dropFirst()
            for statement in statements {
                lookups += 1
                let call = String(statement.prefix { $0 != "}" })
                let carriesValue = call.contains("\\(")
                if !call.contains("bundle: .module") {
                    found.append("\(file.name): no bundle in \(call.prefix(40))")
                }
                if carriesValue != call.contains("locale: locale") {
                    found.append("\(file.name): value \(carriesValue) and locale disagree in \(call.prefix(40))")
                }
            }
        }
        // 33, and the five of the builder's empty and failed states and of a change not saved (F11 S13).
        #expect(lookups == 38, "the scan read \(lookups) lookups for the catalog's 38 keys")
        #expect(found.isEmpty, "\(found.prefix(5))")
    }
}
