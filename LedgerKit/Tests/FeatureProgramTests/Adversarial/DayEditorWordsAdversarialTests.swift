@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: the words (criteria 7 and 9 of the slice). Every text of every model drawn is
/// the brief's "Copy (exact)", a text the brief does not give and the tester lists for Pete, or the lifter's
/// own data; and the new sources hold no text and read nothing ambient.
@Suite("Adversarial F11 S6 · the Day editor's words", .tags(.feature))
nonisolated struct DayEditorWordsAdversarialTests {
    static let number = #"\d+(\.\d+)?"#
    static let rest = #"(\d+s|\d+ min|\d+:\d\d)"#
    static let unit = "(lb|kg)"
    static let sub = "(Barbell|Dumbbell|Cable|Machine|Bodyweight|Kettlebell|Band) · "
        + #"(\+\#(number)/wk|Reps \d+–\d+|Fixed)( · drop)? · RPE \#(number) · (no rest|\#(rest) rest)"#

    /// The brief's "Copy (exact)" for the Day editor, with "kg" beside "lb" (decision #9) and the two kinds of
    /// equipment the brief's chips leave out.
    static let brief = [
        "Program", "Done", #"DAY \d+ OF \d+"#, #"Week \d+ · \d+ exercises? · \d+ sets? · ~\d+ min"#,
        "SUPERSET", #"\d+ exercises back to back · rest after [A-Z]"#, #"\d+[A-Z]?"#, sub,
        #"\d+×\d+"#, "\(number) \(unit)", #"WEEK \d+( · DELOAD| · HELD)?"#,
        #"\d+ × \d+ @ \#(number) \#(unit) · RPE \#(number)"#, #"W\d+ \#(number)( \(deload\))?"#,
        "SETS", "REPS", "REP FLOOR", "TOP OF RANGE", "START LOAD", "TARGET RPE", "REST", #"\d+"#, number, rest,
        "PROGRESSION", "Linear", "Double", "Fixed",
        #"Adds \#(number) \#(unit) a week from \#(number) \#(unit)\. A week with a missed set holds the load\."#,
        #"Adds a rep each week up to \d+, then \+\#(number) \#(unit) back at \d+\."#,
        #"Stays at \#(number) \#(unit) for the whole block\."#, "Drop set",
        #"One extra set at −15% after the last working set\."#,
        #"One extra set at −15%, straight after the last working set\."#,
        "Break out", "Superset with next", "Move up", "Move down", "Remove", #"\+ Add exercise from library"#,
        #"It's scheduled in \d+ weeks?\. Those days become rest\."#, "Delete", "Cancel"
    ]

    /// Texts the brief does not give, by where they are drawn. The first is the plan's decision 6.
    static let notGiven: [String: [String]] = [
        "delete": ["Delete day"],
        "nameLabel": ["Day name"],
        "meta": [#"Week \d+ · No exercises yet"#],
        "strip": [#"W\d+ \#(number) \(held\)"#],
        "name": ["—"],
        "sub": [#"(drop · )?RPE \#(number) · (no rest|\#(rest) rest)"#],
        "spoken": [
            "Superset", "Sets", "Reps", "Rep floor", "Top of range", "Start load", "Target RPE", "Rest",
            #"\d+[A-Z]?, .+"#, #"\d+×\d+ · (\#(number) \#(unit) · \#(sub)|(drop · )?RPE .+ rest)"#
        ]
    ]

    static func texts(of content: DayEditorModel.Content) -> [(place: String, text: String)] {
        let header = content.header
        let confirmation = content.deleteDay.confirmation
        var found: [(String, String)] = [
            ("copy", header.back.title), ("copy", header.position), ("copy", header.done.title),
            ("nameLabel", header.nameLabel), ("meta", header.meta), ("copy", content.addExercise.title),
            ("delete", content.deleteDay.title), ("copy", confirmation.confirm.title), ("copy", confirmation.cancel)
        ]
        found += [confirmation.message].compactMap(\.self).map { ("copy", $0) }
        for group in content.groups {
            found += [group.header?.title, group.header?.note].compactMap(\.self).map { ("copy", $0) }
            found += [group.header?.spokenLabel].compactMap(\.self).map { ("spoken", $0) }
            for row in group.rows {
                found += [("copy", row.index), ("sub", row.sub), ("copy", row.scheme)]
                found += [("spoken", row.spokenLabel), ("spoken", row.spokenValue)]
                found += [row.load].compactMap(\.self).map { ("copy", $0) }
                found += row.name == "—" ? [("name", row.name)] : []
                guard let panel = row.panel else {
                    continue
                }
                let controls = panel.supersetActions + [panel.moveUp, panel.moveDown, panel.remove].compactMap(\.self)
                found += controls.map { ("copy", $0.title) }
                guard let details = panel.details else {
                    continue
                }
                found += [("copy", details.week.eyebrow), ("copy", details.week.line)]
                found += details.strip.entries.map { ("strip", $0.text) }
                found += details.fields.flatMap { [("copy", $0.label), ("copy", $0.value), ("spoken", $0.spokenLabel)] }
                found += [("copy", details.progression.title), ("copy", details.progression.note)]
                found += details.progression.chips.map { ("copy", $0.title) }
                found += [("copy", details.dropSet.title), ("copy", details.dropSet.note)]
            }
        }
        return found
    }

    static func matches(_ text: String, _ patterns: [String]) throws -> Bool {
        try patterns.contains { try Regex($0).wholeMatch(in: text) != nil }
    }

    @Test("Every text drawn is the brief's, or one the tester lists as not given, in its place")
    func everyText_isTheBriefsOrListed() throws {
        var unknown: Set<String> = []
        var listed: Set<String> = []
        var read = 0
        for seed in 1 ... 16 as ClosedRange<UInt64> {
            let (program, dayID) = try AdvDay.random(seed: seed, missing: true)
            var day = program.days[1]
            for place in day.slots.indices where place.isMultiple(of: 2) {
                day.slots[place].misses = [0, 2]
            }
            let edited = ProgramEditing.updateDay(program, day: dayID) { _ in day }
            for opened in [nil] + day.slots.map(\.id) {
                let units: Units = seed.isMultiple(of: 2) ? .kg : .lb
                let input = AdvDay.input(
                    edited, day: dayID, exercises: AdvDay.stored(), units: units, week: Int(seed % 5), open: opened
                )
                for (place, text) in try Self.texts(of: #require(AdvDay.content(input))) {
                    read += 1
                    if try place != "spoken" && Self.matches(text, Self.brief) {
                        continue
                    }
                    if try Self.matches(text, Self.notGiven[place] ?? []) {
                        listed.insert(place)
                    } else {
                        unknown.insert("\(place): \(text)")
                    }
                }
            }
        }
        let isKnown = unknown.isEmpty
        #expect(isKnown, "\(unknown.count) unknown: \(unknown.sorted().prefix(5))")
        #expect(listed == Set(Self.notGiven.keys))
        #expect(read > 2000)
    }
}

nonisolated extension DayEditorWordsAdversarialTests {
    @Test("The confirmation's title is Delete, the day's short title and a question mark, whatever the name holds")
    func deleteTitle_carriesTheShortTitleAsItIs() throws {
        for name in ["Arms", "Legs — heavy — again", "100% %@ %lld", "Día de pierna 🦵", "A — "] {
            var input = try AdvDay.seed(day: 0)
            input.program = ProgramEditing.renameDay(input.program, day: input.day, to: name)
            let stored = try #require(AdvDay.day(input))
            #expect(AdvDay.content(input)?.deleteDay.confirmation.title == "Delete \(stored.shortTitle)?")
            #expect(AdvDay.content(input)?.header.name == stored.name)
        }
    }

    // MARK: - The sources

    static func sources() throws -> [(name: String, code: [String])] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureProgram/DayEditor")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }.map { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
            }
            return (file.lastPathComponent, code)
        }
    }

    @Test("The Day editor's sources read no clock, calendar, locale, zone, random number or stored default")
    func sources_readNothingAmbient() throws {
        let banned = [
            "Date()", "Date.now", ".now", "Calendar.current", "Locale.current", "TimeZone.current",
            "autoupdatingCurrent", "UUID()", ".random", "ProcessInfo", "UserDefaults", "NSLocale", "Calendar(",
            "preferredLanguages", "DispatchTime", "ContinuousClock", "SystemRandom", ".formatted()", "Formatter("
        ]
        var found: [String] = []
        let files = try Self.sources()
        for file in files {
            for (place, line) in file.code.enumerated() {
                found += banned.filter { line.contains($0) }.map { "\(file.name):\(place + 1) \($0)" }
            }
        }
        #expect(files.count == 11, "the scan found \(files.map(\.name))")
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Outside the copy files the Day editor's sources hold no text but the empty one and the separator")
    func sources_holdNoCopyOutsideTheCopyFiles() throws {
        var found: [String] = []
        for file in try Self.sources() where !file.name.hasPrefix("ProgramCopy") {
            for (place, line) in file.code.enumerated() {
                let pieces = line.split(separator: "\"", omittingEmptySubsequences: false)
                let literals = pieces.enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
                found += literals.filter { !["", " · "].contains($0) }.map { "\(file.name):\(place + 1) \"\($0)\"" }
                let lookups = ["String(localized", "LocalizedStringKey", "NSLocalizedString", "bundle:"]
                found += lookups.filter { line.contains($0) }.map { "\(file.name):\(place + 1) \($0)" }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Every lookup of the Day editor's copy files names the module's bundle, and one with a value the locale")
    func copyFiles_everyValueCarriesTheLocale() throws {
        var found: [String] = []
        var lookups = 0
        for file in try Self.sources() where file.name.hasPrefix("ProgramCopy") {
            for statement in file.code.joined(separator: "\n").components(separatedBy: "localized:").dropFirst() {
                lookups += 1
                let call = String(statement.prefix { $0 != "}" })
                if !call.contains("bundle: .module") {
                    found.append("\(file.name): no bundle in \(call.prefix(40))")
                }
                if call.contains("\\(") != call.contains("locale: locale") {
                    found.append("\(file.name): value and locale disagree in \(call.prefix(40))")
                }
            }
        }
        #expect(lookups >= 60, "the scan read \(lookups) lookups")
        #expect(found.isEmpty, "\(found.prefix(5))")
    }
}
