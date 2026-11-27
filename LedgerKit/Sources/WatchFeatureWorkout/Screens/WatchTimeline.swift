import SwiftUI

/// Where the live screens take their time from, as the phone's `WorkoutTimeline` (FeatureWorkout): in the app it runs
/// by the wall clock; a preview or a snapshot fixes it at a moment, so what it draws is the same on every run. The
/// countdown and the elapsed time are `Text(timerInterval:)`, which tick with no view update (and with the wrist down);
/// the ring is read again by a `TimelineView`, once a second, and once a minute with the wrist down (criterion 12).
nonisolated struct WatchTimeline: Equatable, Sendable {
    /// The moment time stands still at; nil in the app, where it runs.
    var pausedAt: Date?

    static let live = WatchTimeline(pausedAt: nil)

    static func fixed(at moment: Date) -> WatchTimeline {
        WatchTimeline(pausedAt: moment)
    }

    /// The moment a `TimelineView` draws at: its own, unless time stands still.
    func moment(_ date: Date) -> Date {
        pausedAt ?? date
    }

    /// Counts from `start` up ("24:22"), or down to `end` ("1:15"), by the wall clock. A moment that is not a finite
    /// time reads `fallback`: SwiftUI traps on a timer that starts at no time at all. A countdown with time standing
    /// still reads `fallback` too, the presentation's reading at that moment: a paused countdown is drawn counting up
    /// (seen 2026-11-27 in the watchOS 27.0 simulator's snapshots: "0:30" for 60 s left of a 90 s rest).
    func timer(from start: Date, to end: Date = .distantFuture, countsDown: Bool, fallback: String) -> Text {
        let isCountable = [start, end].allSatisfy(\.timeIntervalSinceReferenceDate.isFinite) && start <= end
        guard isCountable, !(countsDown && pausedAt != nil) else {
            return Text(verbatim: fallback)
        }
        return Text(timerInterval: start ... end, pauseTime: pausedAt, countsDown: countsDown)
    }
}

/// `nonisolated`, so the key `@Entry` generates is not main-actor-isolated by this module's default.
nonisolated extension EnvironmentValues {
    /// The live screens' time: the wall clock unless a preview or a snapshot fixes it.
    @Entry var watchTimeline = WatchTimeline.live
}
