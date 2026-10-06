import Foundation
import LedgerTestSupport
import Testing

/// F09 S3 criterion 11, read from the sources: Today takes its clock, calendar, locale and time zone from the
/// input and from nowhere else, and its presentation never turns a weight or a volume into a `Double`.
///
/// The check reads every Swift file of the module, the views and the store when they come. It reads code, and
/// the code inside a string interpolation, where a copy member could format a date; it does not read comments or
/// a literal's own text. It reads spellings, not types: a clock reached through a name of the module's own is
/// for review to find.
@Suite("FeatureToday sources", .tags(.feature))
nonisolated struct FeatureTodaySourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, written without spaces: a
    /// moment made here, a current or self-updating value, a calendar built in place (it takes the device's
    /// zone), a format style or a formatter with the device's defaults.
    static let ambient = [
        "Date()", "Date.init()", "Date.now", "Date(timeIntervalSinceNow", ":.now", "=.now", "(.now",
        "Calendar.current", "Calendar.autoupdatingCurrent", "Calendar(identifier:", "Locale.current",
        "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent", "locale:.current",
        "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent", ".dateTime", ".formatted()",
        "DateFormatter(", "NumberFormatter(", "DateComponentsFormatter("
    ]

    /// The spellings that name a binary floating-point number, or turn a decimal into one.
    static let inexact = ["Double", "Float", "CGFloat", "TimeInterval", ".doubleValue", ".floatValue"]

    /// The lines of `source` on which `spelling` stands in code: the file's own, or a string interpolation's.
    static func lines(of spelling: String, in source: SwiftSource) -> [Int] {
        let interpolated = source.literals.flatMap { literal in
            literal.interpolations
                .filter { $0.filter { !$0.isWhitespace }.contains(spelling) }
                .map { _ in literal.line }
        }
        return Set(source.lines(ofCode: spelling) + interpolated).sorted()
    }

    /// Each use of one of `spellings` in the module's files that `isRead` accepts, as "file:line: spelling".
    static func uses(of spellings: [String], inFiles isRead: (String) -> Bool = { _ in true }) throws -> [String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureToday")
        try #require(sources.count >= 10, "FeatureToday's sources were not found")
        return sources.sorted { $0.key < $1.key }.filter { isRead($0.key) }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    @Test("No file of FeatureToday reads the clock, the current calendar, the current locale or the current time zone")
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("The presentation, the copy and the model never name Double: weights and volumes stay exact")
    func presentation_neverNamesDouble() throws {
        let files = try Self.uses(of: Self.inexact) {
            $0.hasPrefix("TodayPresentation") || $0.hasPrefix("TodayCopy") || $0.hasPrefix("TodayModel")
        }
        #expect(files == [])
    }

    @Test("The check reads code and the code of an interpolation, not comments or text, and finds what is there")
    func check_findsASpellingInCodeAndInInterpolations() {
        let source = SwiftSource("""
        /// Never `Date()` here.
        let now = Date ()
        let zone = TimeZone
            .current
        let text = "Calendar.current, .dateTime and Date() are only words here"
        let line = "Started \\(start.formatted(.dateTime.weekday())) at \\(Date.now.formatted())"
        let kilograms = "\\(weight.doubleValue) kg"
        """)
        #expect(Self.lines(of: "Date()", in: source) == [2])
        #expect(Self.lines(of: "TimeZone.current", in: source) == [3])
        #expect(Self.lines(of: "Calendar.current", in: source) == [])
        #expect(Self.lines(of: ".dateTime", in: source) == [6])
        #expect(Self.lines(of: "Date.now", in: source) == [6])
        #expect(Self.lines(of: ".formatted()", in: source) == [6])
        #expect(Self.lines(of: ".doubleValue", in: source) == [7])
        // Every spelling of the two lists is found when it stands in code.
        for spelling in Self.ambient + Self.inexact {
            #expect(Self.lines(of: spelling, in: SwiftSource("let value = call(\(spelling)")) == [1], "\(spelling)")
        }
    }
}
