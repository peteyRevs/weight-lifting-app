import Foundation
import LedgerTestSupport
import Testing

/// F10 S4 criterion 8, read from the sources: the workout takes its clock, calendar, locale and time zone from
/// what is injected and from nowhere else, and counts no time itself (the brief's definition of done: no
/// `Date()` and no `Timer` in FeatureWorkout). Time on screen comes from `WorkoutTimeline`; the time of an
/// event from `@Dependency(\.date)`.
///
/// The check reads every Swift file of the module, as `FeatureTodaySourceTests` does for Today: code, and
/// the code inside a string interpolation; not comments or a literal's own text. It reads spellings, not
/// types: a clock reached through a name of the module's own is for review to find.
@Suite("FeatureWorkout sources", .tags(.feature))
nonisolated struct FeatureWorkoutSourceTests {
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

    /// The spellings that count time by ticks, or draw a time that a test cannot fix: a timer of the module's
    /// own, a sleep, and SwiftUI's timer style, which has no pause.
    static let ticking = [
        "Timer.scheduledTimer", "Timer.publish", "=Timer(", "Timer(timeInterval", "Timer(fire", "Task.sleep",
        "style:.timer", "ContinuousClock(", "SuspendingClock("
    ]

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
        let sources = try CopyAudit.sources(ofModule: "FeatureWorkout")
        try #require(sources.count >= 14, "FeatureWorkout's sources were not found")
        return sources.sorted { $0.key < $1.key }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    @Test("No file of FeatureWorkout reads the clock, the current calendar, the current locale or the current zone")
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("No file of FeatureWorkout counts time itself: no timer, no sleep, no timer style without a pause")
    func sources_neverCountTime() throws {
        #expect(try Self.uses(of: Self.ticking) == [])
    }

    @Test("The elapsed time is drawn in one place, and that place takes its pause from the timeline")
    func elapsedTime_isDrawnByTheTimelineAlone() throws {
        let uses = try Self.uses(of: ["timerInterval:"])
        #expect(uses.count == 1)
        #expect(uses.first?.hasPrefix("Views/WorkoutTimeline.swift:") == true, "\(uses)")
        let timeline = try #require(CopyAudit.sources(ofModule: "FeatureWorkout")["Views/WorkoutTimeline.swift"])
        #expect(Self.lines(of: "pauseTime:pausedAt", in: SwiftSource(timeline)).count == 1)
    }

    @Test("The check reads code and the code of an interpolation, not comments or text, and finds what is there")
    func check_findsASpellingInCodeAndInInterpolations() {
        let source = SwiftSource("""
        /// Never `Date()` here, and no Task.sleep either.
        let now = Date ()
        let zone = TimeZone
            .current
        let text = "Calendar.current, .dateTime and Date() are only words here"
        let line = "Started \\(start.formatted(.dateTime.weekday())) at \\(Date.now.formatted())"
        """)
        #expect(Self.lines(of: "Date()", in: source) == [2])
        #expect(Self.lines(of: "TimeZone.current", in: source) == [3])
        #expect(Self.lines(of: "Calendar.current", in: source) == [])
        #expect(Self.lines(of: ".dateTime", in: source) == [6])
        #expect(Self.lines(of: "Date.now", in: source) == [6])
        #expect(Self.lines(of: "Task.sleep", in: source) == [])
        // Every spelling of the two lists is found when it stands in code.
        for spelling in Self.ambient + Self.ticking {
            #expect(Self.lines(of: spelling, in: SwiftSource("let value = call(\(spelling)")) == [1], "\(spelling)")
        }
    }
}
