@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: purity (S3 criterion 11). A scan of the module's sources, written here, for a clock, a
/// calendar, a locale or a time zone of the module's own, for `Double`, and for words outside the copy files;
/// and what an injected locale and calendar do to the model, since the scan cannot see a default argument.
@Suite("Adversarial F09 S3 · purity", .tags(.feature))
nonisolated struct TodayPurityAdversarialTests {
    typealias Support = TodayAdversarial

    /// A source file of the module with its comments blanked, line by line.
    struct Source {
        let name: String
        let lines: [String]
    }

    static func sources() throws -> [Source] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Support.sources.path(percentEncoded: false))
        return try names.filter { $0.hasSuffix(".swift") }.sorted().map { name in
            let text = try String(contentsOf: Support.sources.appending(path: name), encoding: .utf8)
            return Source(name: name, lines: text.components(separatedBy: "\n").map(code))
        }
    }

    /// `line` without a `//` comment that begins outside a string literal.
    static func code(_ line: String) -> String {
        var isInString = false
        var previous: Character = " "
        var kept = ""
        for character in line {
            if character == "\"", previous != "\\" {
                isInString.toggle()
            }
            if character == "/", previous == "/", !isInString {
                return String(kept.dropLast())
            }
            kept.append(character)
            previous = character
        }
        return kept
    }

    static func hits(_ pattern: String, in sources: [Source]) -> [String] {
        sources.flatMap { source in
            source.lines.enumerated().compactMap { index, line in
                line.range(of: pattern, options: .regularExpression) == nil ? nil : "\(source.name):\(index + 1)"
            }
        }
    }

    static let forbidden = [
        #"\bDate\(\s*\)"#, #"\bDate\.now\b"#, #"(?<![\w)\]?])\.now\b"#, #"\.(current|autoupdatingCurrent)\b"#,
        #"\b(ProcessInfo|NSTimeZone|NSCalendar|NSLocale|CFAbsoluteTime\w*|DispatchTime)\b"#,
        #"\b(ContinuousClock|SuspendingClock|UserDefaults)\b"#, #"\bBundle\.main\b"#,
        #"\b(DateFormatter|NumberFormatter|ISO8601DateFormatter|DateComponentsFormatter|MeasurementFormatter)\b"#,
        #"String\(format:"#, #"\.formatted\(\s*\)"#, #"\bCalendar\(identifier:"#, #"\bLocale\(identifier:"#,
        #"\bTimeZone\((identifier|secondsFromGMT|abbreviation):"#,
        #"\b(Double|Float|Float80|CGFloat|TimeInterval)\b"#, #"\b(doubleValue|floatValue|NSDecimalNumber|NSNumber)\b"#,
        #"\b(random|shuffled|UUID\(\))\b"#
    ]

    @Test("No source of the module reaches for a clock, a calendar, a locale, a zone or a Double", arguments: forbidden)
    func sources_reachForNothingOfTheirOwn(_ pattern: String) throws {
        let sources = try Self.sources()
        #expect(sources.count >= 10, "the scan found only \(sources.count) files")
        #expect(Self.hits(pattern, in: sources) == [])
    }

    @Test("Outside the copy files no source holds a word a lifter could read, or looks one up")
    func words_liveInTheCopyFiles() throws {
        let other = try Self.sources().filter { !$0.name.hasPrefix("TodayCopy") }
        // A literal with a letter in it, once its interpolations are taken out.
        let worded = other.flatMap { source in
            source.lines.enumerated().compactMap { index, line -> String? in
                let bare = line.replacingOccurrences(of: #"\\\([^"]*?\)"#, with: "", options: .regularExpression)
                let hasWords = bare.range(of: #""[^"]*[A-Za-z][^"]*""#, options: .regularExpression) != nil
                return hasWords ? "\(source.name):\(index + 1)" : nil
            }
        }
        #expect(worded == [])
        #expect(Self.hits(#"String\(\s*localized:|LocalizedStringKey|NSLocalizedString|\bText\("#, in: other) == [])
    }

    @Test("Outside the copy files the one literal that joins texts is the middle dot between spaces")
    func joiner_isTheMiddleDot() throws {
        let other = try Self.sources().filter { !$0.name.hasPrefix("TodayCopy") }
        // Every string literal that is not empty and not the separator: S3 criterion 10 joins fragments with
        // " · ", and standards §7 keeps every other text a lifter reads or hears in the catalog.
        let literals = other.flatMap { source in
            source.lines.enumerated().compactMap { index, line -> String? in
                let rest = line.replacingOccurrences(of: "\" · \"", with: "").replacingOccurrences(of: "\"\"", with: "")
                return rest.contains("\"") ? "\(source.name):\(index + 1)" : nil
            }
        }
        #expect(literals == [])
    }

    /// The text of every `String(localized: …)` call in `text`, from its opening parenthesis to the one that
    /// closes it.
    static func lookups(in text: String) -> [String] {
        var calls: [String] = []
        var rest = Substring(text)
        while let start = rest.range(of: #"String\(\s*localized:"#, options: .regularExpression) {
            var depth = 0
            var end = start.lowerBound
            for index in rest[start.lowerBound...].indices {
                depth += rest[index] == "(" ? 1 : 0
                depth -= rest[index] == ")" ? 1 : 0
                end = index
                if depth == 0, rest[index] == ")" {
                    break
                }
            }
            calls.append(String(rest[start.lowerBound ... end]))
            rest = rest[rest.index(after: end)...]
        }
        return calls
    }

    @Test("Every lookup reads this module's catalog, and one that carries a value takes the injected locale")
    func lookups_takeTheInjectedLocale() throws {
        let copy = try Self.sources().filter { $0.name.hasPrefix("TodayCopy") }
        let calls = copy.flatMap { Self.lookups(in: $0.lines.joined(separator: "\n")) }
        // Round 1's 49, the four spoken lines of criterion 14 and the sentences of criteria 16 and 17.
        #expect(calls.count == 55, "the catalog holds 55 keys")
        let withoutBundle = calls.filter { !$0.contains("bundle: .module") }.map { String($0.prefix(60)) }
        #expect(withoutBundle == [])
        let carriesAValue = calls.filter { $0.contains("\\(") }
        let withoutLocale = carriesAValue.filter { !$0.contains("locale: locale") }.map { String($0.prefix(60)) }
        #expect(carriesAValue.count >= 25)
        #expect(withoutLocale == [])
    }
}
