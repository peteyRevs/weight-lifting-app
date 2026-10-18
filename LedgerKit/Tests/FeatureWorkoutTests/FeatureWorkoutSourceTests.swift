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

    /// The spellings that make a task of the module's own (M1 store convention; standards §3 and §4): work is
    /// run from a view's `.task`, which SwiftUI ends with the view.
    static let unstructured = ["Task{", "Task(", "Task.detached", "Task.init", "Task<"]

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

    @Test("No file of FeatureWorkout starts a task of its own: no store, launcher or view outlives its `.task`")
    func sources_startNoTaskOfTheirOwn() throws {
        #expect(try Self.uses(of: Self.unstructured) == [])
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
        for spelling in Self.ambient + Self.ticking + Self.unstructured {
            #expect(Self.lines(of: spelling, in: SwiftSource("let value = call(\(spelling)")) == [1], "\(spelling)")
        }
    }

    /// F10 S6, the orchestrator's ruling during G1: the tester's scan (`WorkoutWordsAdversarialTests`) now
    /// passes the Domain's type `RestTimer`, and nothing wider. This is the control: a timer of
    /// Foundation's planted beside it is still caught, and so is a `TimelineView`.
    @Test("The tester's scan passes RestTimer and still catches a planted Timer and a TimelineView", arguments: [
        ("let rest: RestTimer? = state.shownRest", false),
        ("Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }", true),
        ("let rest: RestTimer? = nil; Timer.publish(every: 1, on: .main, in: .common)", true),
        ("var timer: Timer?", true),
        ("TimelineView(.periodic(from: start, by: 1)) { _ in }", true)
    ])
    func testersScan_stillCatchesATimer(line: String, isCaught: Bool) {
        let code = WorkoutWordsAdversarialTests.scanned(Substring(line))
        #expect(WorkoutWordsAdversarialTests.forbidden.contains { code.contains($0) } == isCaught)
    }

    // MARK: F10 S7a

    /// Criterion 20: posting an announcement is ambient, as a clock is. The store hands its texts to the
    /// injected `AnnouncementsClient`; the system's own calls are `LedgerAppKit`'s.
    static let announcing = ["UIAccessibility.post", "UIAccessibilityPostNotification", "AccessibilityNotification"]

    @Test("No file of FeatureWorkout posts an accessibility announcement itself")
    func sources_postNoAnnouncement() throws {
        #expect(try Self.uses(of: Self.announcing) == [])
        for spelling in Self.announcing {
            #expect(Self.lines(of: spelling, in: SwiftSource("call(\(spelling)")) == [1], "\(spelling)")
        }
    }

    /// Criterion 24: the texts this slice adds are looked up in `WorkoutCopy+Finish.swift`, and the rest's
    /// announcement in `WorkoutCopy+Rest.swift`; no other file holds one of their keys.
    @Test("The slice's lookups are in WorkoutCopy+Finish, and the announcement's in WorkoutCopy+Rest")
    func finishLookups_areInTheirCopyFiles() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureWorkout")
        let finish = [
            "End workout?", "Save workout", "Keep lifting", "sets logged", " lb moved", " kg moved",
            "Couldn't save this workout", "It's still on this iPhone. Try again.", "\"Try again\""
        ]
        for text in finish + ["remaining\""] {
            let home = text == "remaining\"" ? "WorkoutCopy+Rest.swift" : "WorkoutCopy+Finish.swift"
            let holders = sources.filter { $0.value.contains("localized: \"") && Self.looksUp(text, in: $0.value) }
            #expect(holders.keys.sorted() == [home], "\(text)")
        }
    }

    /// Whether a line of `source` that makes a lookup holds `text`.
    static func looksUp(_ text: String, in source: String) -> Bool {
        source.split(separator: "\n").contains { $0.contains("localized:") && $0.contains(text) }
    }

    /// Criterion 1 and ruling R2: "End workout?" is a sheet. The system's dialog is gone from the cover's
    /// content; the conflict dialog, which is the launcher's, is not this slice's.
    @Test("The cover's content presents End workout? as a sheet, and no system dialog")
    func root_presentsASheet() throws {
        let root = try #require(CopyAudit.sources(ofModule: "FeatureWorkout")["WorkoutRoot.swift"])
        let source = SwiftSource(root)
        #expect(Self.lines(of: "confirmationDialog", in: source) == [])
        #expect(Self.lines(of: ".sheet(isPresented:shows(.finish,else:.keepLifting))", in: source).count == 1)
        #expect(Self.lines(of: ".task(id:store.saveAttempt)", in: source).count == 1)
        // The failed save's alert is one presentation for each attempt (the notes, "Fix round 1"), and the
        // system's own dismissal of an alert takes down that alert's dialog alone.
        #expect(Self.lines(of: "SaveFailedAlert(store:store,model:unsaved).id(store.saveAttempt)", in: source)
            .count == 1)
        #expect(Self.lines(of: "else:.dismissFailure", in: source) == [])
    }
}
