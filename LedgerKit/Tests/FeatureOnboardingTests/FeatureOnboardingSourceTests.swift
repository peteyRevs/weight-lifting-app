import Foundation
import LedgerTestSupport
import Testing

/// F08 S2 criterion 11, read from the sources: onboarding takes its clock, ids, calendar and locale from what is
/// injected and from nowhere else, starts no task of its own and counts no time (the brief's "Store
/// conventions": M1 store convention, standards §3, §4 and §11).
///
/// The check reads every Swift file of the module, as `FeatureTodaySourceTests` does for Today: code, and the code
/// inside a string interpolation; not comments or a literal's own text. It reads spellings, not types: a clock
/// reached through a name of the module's own is for review to find.
@Suite("FeatureOnboarding sources", .tags(.feature))
nonisolated struct FeatureOnboardingSourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, written without spaces: a
    /// moment made here, a current or self-updating value, a calendar built in place (it takes the device's
    /// zone), a format style or a formatter with the device's defaults.
    static let ambient = [
        "Date()", "Date.init()", "Date.now", "Date(timeIntervalSinceNow", ":.now", "=.now", "(.now",
        "Calendar.current", "Calendar.autoupdatingCurrent", "Calendar(identifier:", "Locale.current",
        "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent", "locale:.current",
        "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent", ".dateTime", ".formatted(",
        "DateFormatter(", "NumberFormatter(", "DateComponentsFormatter(", "UUID()"
    ]

    /// The spellings that count time by ticks or redraw on a clock of their own.
    static let ticking = [
        "Timer.scheduledTimer", "Timer.publish", "=Timer(", "Timer(timeInterval", "Timer(fire", "Task.sleep",
        "TimelineView", "ContinuousClock(", "SuspendingClock("
    ]

    /// The spellings that make a task or a queue of the module's own: work is run from the root's `.task`s,
    /// which SwiftUI ends with the view.
    static let unstructured = ["Task{", "Task(", "Task.detached", "Task.init", "Task<", "DispatchQueue"]

    /// The lines of `source` on which `spelling` stands in code: the file's own, or a string interpolation's.
    static func lines(of spelling: String, in source: SwiftSource) -> [Int] {
        let interpolated = source.literals.flatMap { literal in
            literal.interpolations
                .filter { $0.filter { !$0.isWhitespace }.contains(spelling) }
                .map { _ in literal.line }
        }
        return Set(source.lines(ofCode: spelling) + interpolated).sorted()
    }

    /// Each use of one of `spellings` in the module's files, as "file:line: spelling".
    static func uses(of spellings: [String]) throws -> [String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureOnboarding")
        try #require(sources.count >= 11, "FeatureOnboarding's sources were not found")
        return sources.sorted { $0.key < $1.key }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    @Test("No file of FeatureOnboarding reads the clock, the current calendar, locale or zone, or makes an id")
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("No file of FeatureOnboarding counts time itself: no timer, no sleep, no timeline view")
    func sources_neverCountTime() throws {
        #expect(try Self.uses(of: Self.ticking) == [])
    }

    @Test("No file of FeatureOnboarding starts a task or a queue of its own: the root's `.task`s run the work")
    func sources_startNoTaskOfTheirOwn() throws {
        #expect(try Self.uses(of: Self.unstructured) == [])
    }

    @Test("The check finds each spelling in code and in an interpolation, not in comments or text")
    func check_findsASpellingInCodeAndInInterpolations() {
        let source = SwiftSource("""
        /// Never `Task {}` here.
        let task = Task {
        let text = "Timer, TimelineView and Date() are only words here"
        let line = "Saved at \\(Date.now.formatted(.dateTime))"
        """)
        #expect(Self.lines(of: "Task{", in: source) == [2])
        #expect(Self.lines(of: "TimelineView", in: source) == [])
        #expect(Self.lines(of: "Date.now", in: source) == [4])
        #expect(Self.lines(of: ".formatted(", in: source) == [4])
        // Every spelling of the three lists is found when it stands in code.
        for spelling in Self.ambient + Self.ticking + Self.unstructured {
            #expect(Self.lines(of: spelling, in: SwiftSource("let value = call(\(spelling)")) == [1], "\(spelling)")
        }
    }
}
