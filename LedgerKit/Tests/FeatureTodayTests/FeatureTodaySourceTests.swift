import Foundation
import LedgerTestSupport
import Testing

/// F09 S3 criterion 11, read from the sources: Today takes its clock, calendar, locale and time zone from the
/// input and from nowhere else, and its presentation never turns a weight or a volume into a `Double`.
@Suite("FeatureToday sources", .tags(.feature))
nonisolated struct FeatureTodaySourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, written without spaces.
    static let ambient = [
        "Date()", "Date.now", "Date(timeIntervalSinceNow", "Calendar.current", "Calendar.autoupdatingCurrent",
        "Locale.current", "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent",
        "locale:.current", "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent",
        ":.now", "=.now", "(.now"
    ]

    /// Each use of one of `spellings` in the code of the module's files that `isRead` accepts, as "file:line: use".
    static func uses(of spellings: [String], inFiles isRead: (String) -> Bool = { _ in true }) throws -> [String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureToday")
        try #require(sources.count >= 10, "FeatureToday's sources were not found")
        return sources.sorted { $0.key < $1.key }.filter { isRead($0.key) }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                source.lines(ofCode: spelling).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    @Test("No file of FeatureToday reads the clock, the current calendar, the current locale or the current time zone")
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("The presentation and the copy never name Double: weights and volumes stay exact")
    func presentation_neverNamesDouble() throws {
        let files = try Self.uses(of: ["Double", "Float", "CGFloat", "TimeInterval"]) {
            $0.hasPrefix("TodayPresentation") || $0.hasPrefix("TodayCopy") || $0.hasPrefix("TodayModel")
        }
        #expect(files == [])
    }

    @Test("The check reads code, not comments, and finds a spelling when it is there")
    func check_findsASpellingInCodeOnly() {
        let source = SwiftSource("""
        /// Never `Date()` here.
        let now = Date ()
        let zone = TimeZone
            .current
        let text = "Calendar.current"
        """)
        #expect(source.lines(ofCode: "Date()") == [2])
        #expect(source.lines(ofCode: "TimeZone.current") == [3])
        #expect(source.lines(ofCode: "Calendar.current") == [])
    }
}
