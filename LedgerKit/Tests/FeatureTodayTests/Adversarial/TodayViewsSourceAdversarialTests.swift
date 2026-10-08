@testable import FeatureToday
import Foundation
import LedgerTestSupport
import Testing

/// F09 S4, gate G2: scans of the views' sources, written here (criteria 1, 4 and 5; standards §7). The S3 scan
/// reads the module's top folder only, so nothing in `Views/` was under it. Also this tester's ruling on the
/// S3 word scan, which the slice taught to skip `*+Previews.swift`: the skip is right for a file wholly inside
/// `#if DEBUG`, and only for that; the tests at the end hold the previews to it.
@Suite("Adversarial F09 S4 · the views' sources", .tags(.feature))
nonisolated struct TodayViewsSourceAdversarialTests {
    typealias Scan = TodayPurityAdversarialTests

    /// The files of `FeatureToday/Views`, comments blanked.
    static func views() throws -> [Scan.Source] {
        let folder = TodayAdversarial.sources.appending(path: "Views")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        return try names.filter { $0.hasSuffix(".swift") }.sorted().map { name in
            let text = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
            return Scan.Source(name: name, lines: text.components(separatedBy: "\n").map(Scan.code))
        }
    }

    /// `line` with its string literals emptied, so a scan for code does not read a text.
    static func withoutLiterals(_ line: String) -> String {
        line.replacingOccurrences(of: #""(\\.|[^"\\])*""#, with: "\"\"", options: .regularExpression)
    }

    static func bare(_ sources: [Scan.Source]) -> [Scan.Source] {
        sources.map { Scan.Source(name: $0.name, lines: $0.lines.map(withoutLiterals)) }
    }

    @Test("The scan reads the thirteen files of Views")
    func scan_readsEveryView() throws {
        let names = try Self.views().map(\.name)
        #expect(names.count == 13, "\(names)")
    }

    /// The S3 list without its `Double` family: a view may measure in `CGFloat`.
    static let forbidden = Scan.forbidden.filter { !$0.contains("CGFloat") } + [
        #"@Dependency\b"#, #"\bimport LedgerDependencies\b"#, #"\bTimelineView\b"#, #"\bTimer\b"#,
        #"\bwithAnimation\b"#, #"\.animation\("#, #"\.transition\("#, #"\bsymbolEffect\b"#, #"\bphaseAnimator\b"#,
        #"\.task\b"#, #"\bTask\s*\{"#, #"\bTask\("#, #"\.onAppear\b"#, #"\.refreshable\b"#,
        #"\bDispatchQueue\b"#, #"\bNotificationCenter\b"#, #"\.formatted\("#, #"\.uppercased\(|\.capitalized\b"#,
        #"\bTodayPresentation\b"#, #"\bTodayInput\b"#
    ]

    @Test(
        "No view reads a clock, a calendar or a locale, formats a value, runs a task or animates by itself",
        arguments: forbidden
    )
    func views_reachForNothing(_ pattern: String) throws {
        #expect(try Scan.hits(pattern, in: Self.bare(Self.views())) == [])
    }

    @Test("The one view that watches a value change is the screen, which takes its sheet away with the list")
    func views_onChange_isTheScreensAlone() throws {
        let hits = try Scan.hits(#"\.onChange\b|\.onReceive\b|\.onDisappear\b"#, in: Self.bare(Self.views()))
        #expect(hits.count == 1 && hits.allSatisfy { $0.hasPrefix("TodayScreen.swift:") }, "\(hits)")
    }

    @Test("The copy a view asks for is the timer line, its spoken line and the two texts of the failed state")
    func views_copyLookups_areTheFourRuledIn() throws {
        let lines = try Self.bare(Self.views()).flatMap { source in
            source.lines.filter { $0.contains("TodayCopy.") }.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let members = lines.flatMap { line in
            line.matches(of: /TodayCopy\.(\w+)/).map { String($0.1) }
        }
        #expect(members.sorted() == ["failedBody", "failedTitle", "resume", "resumeWorkout"], "\(members)")
        #expect(lines.count(where: { $0.contains("TodayCopy.resume(since:") }) == 1, "\(lines)")
    }

    @Test("No view holds a text a lifter reads: the only literals are identifiers and symbol names")
    func views_holdNoWords() throws {
        let allowed = #"(\.accessibilityIdentifier\(|systemImage: |identifier: )"[A-Za-z0-9.]+""#
        let worded = try Self.views().flatMap { source in
            source.lines.enumerated().compactMap { index, line -> String? in
                let rest = line.replacingOccurrences(of: allowed, with: "", options: .regularExpression)
                return rest.contains("\"") ? "\(source.name):\(index + 1)" : nil
            }
        }
        #expect(worded == [])
        #expect(try Scan.hits(#"\bText\(\s*""#, in: Self.views()) == [])
        #expect(try Scan.hits(#"localized:|LocalizedStringKey|NSLocalizedString"#, in: Self.bare(Self.views())) == [])
    }

    @Test("No view writes a colour, a font or a number of its own: tokens and components only")
    func views_useTokensOnly() throws {
        let raw = [
            #"\bColor\b"#, #"\bUIColor\b"#, #"\bFont\b"#, #"\bUIFont\b"#, #"\.font\("#, #"\.system\("#,
            #"\.(bold|italic|fontWeight|tracking|kerning|opacity|minimumScaleFactor|lineSpacing)\("#,
            #"\.(white|black|gray|red|orange|primary|secondary|tertiary)\b"#, #"\bLedgerRGBA\b"#
        ]
        let sources = try Self.bare(Self.views())
        for pattern in raw {
            #expect(Scan.hits(pattern, in: sources) == [], "\(pattern)")
        }
        // A number other than 0: a spacing, a radius, a size, a line limit, a scale. VoiceOver's sort priority
        // is an order, not a measure.
        let measured = sources.map { source in
            Scan.Source(name: source.name, lines: source.lines.map {
                $0.replacingOccurrences(
                    of: #"\.accessibilitySortPriority\(\d+\)"#,
                    with: "",
                    options: .regularExpression
                )
            })
        }
        let numbers = Scan.hits(#"(?<![\w.])(?!0\b)\d+(\.\d+)?\b"#, in: measured)
        #expect(numbers == [])
    }
}

// MARK: - The previews (this tester's ruling on the edit of the S3 word scan)

nonisolated extension TodayViewsSourceAdversarialTests {
    static func previews() throws -> [Scan.Source] {
        try Scan.sources().filter { $0.name.hasSuffix("+Previews.swift") }
    }

    @Test("A previews file, which the word scan skips, is wholly inside #if DEBUG (standards §7)")
    func previews_areDebugOnly() throws {
        let previews = try Self.previews()
        #expect(previews.map(\.name) == ["Today+Previews.swift"])
        for source in previews {
            let code = source.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let body = code.drop { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
            #expect(body.first == "#if DEBUG", "\(source.name) begins \(body.first ?? "empty")")
            #expect(body.last == "#endif", "\(source.name) ends \(body.last ?? "empty")")
            #expect(
                body.count(where: { $0.hasPrefix("#if") }) == 1 && !body.contains { $0.hasPrefix("#else") },
                "\(source.name) has more than the one condition"
            )
        }
    }

    @Test("No file but a previews file and a copy file is skipped by name: nothing else ends in Previews")
    func previews_skipIsNotWider() throws {
        let skipped = try Scan.sources().filter { !Scan.holdsNoCopy($0) }.map(\.name)
        #expect(skipped == ["Today+Previews.swift", "TodayCopy+Cards.swift", "TodayCopy.swift"], "\(skipped)")
        let nested = try Self.views().filter { $0.name.contains("Preview") || $0.name.hasPrefix("TodayCopy") }
        #expect(nested.map(\.name) == [], "a view file named like a skipped one")
    }

    @Test("The only words in the previews are the names of the registry's cases and of the #Previews themselves")
    func previews_wordsAreTheCaseNames() throws {
        for source in try Self.previews() {
            let worded = source.lines.enumerated().compactMap { index, line -> String? in
                let isCase = line.range(
                    of: #"^\s*(case \w+ = "[^"\\]+"|#Preview\("[^"\\]+"\) \{)$"#, options: .regularExpression
                ) != nil
                let hasLiteral = line.replacingOccurrences(of: "\"\"", with: "").contains("\"")
                return hasLiteral && !isCase ? "\(source.name):\(index + 1)" : nil
            }
            #expect(worded == [])
            let bare = Self.bare([source])
            #expect(Scan.hits(#"localized:|LocalizedStringKey|NSLocalizedString|\bText\(|\bLabel\("#, in: bare) == [])
            #expect(Scan.hits(#"\bTodayCopy\."#, in: bare) == [], "a preview words something itself")
        }
    }

    @Test("A preview's name is a developer's: no case name is a text of the catalog's that a view might borrow")
    func previews_namesAreNotDrawnByAView() throws {
        let uses = try Scan.hits(#"\.rawValue\b"#, in: Self.bare(Self.views()))
        #expect(uses == [], "a view draws an enum's raw value")
    }
}
