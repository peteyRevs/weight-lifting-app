import SwiftUI

/// Where the workout's views take their time from: the one value that says whether time runs. In the app
/// it runs by the wall clock; a preview or a test fixes it at a moment, so what it draws is the same on
/// every run. No view of the workout reads a clock of its own.
nonisolated struct WorkoutTimeline: Equatable, Sendable {
    /// The moment time stands still at; nil in the app, where it runs.
    var pausedAt: Date?

    /// The wall clock.
    static let live = WorkoutTimeline(pausedAt: nil)

    /// Time standing still at `moment`.
    static func fixed(at moment: Date) -> WorkoutTimeline {
        WorkoutTimeline(pausedAt: moment)
    }

    /// The time since `start`, counting up by the wall clock without a view update a second: "0:00",
    /// "24:22", and "1:01:05" from an hour on, as `ClockText.elapsed` writes it. Before `start` it reads
    /// "0:00".
    ///
    /// A start that no calendar holds (it can come from a peer's envelope) counts from the far future, and
    /// so reads "0:00": a range cannot be made from it.
    func elapsed(since start: Date) -> Text {
        let isCountable = start >= .distantPast && start <= .distantFuture
        return Text(
            timerInterval: (isCountable ? start : .distantFuture) ... .distantFuture,
            pauseTime: pausedAt,
            countsDown: false
        )
    }
}

/// `nonisolated`, so the key `@Entry` generates is not main-actor-isolated by this module's default.
nonisolated extension EnvironmentValues {
    /// The workout's time: the wall clock unless a preview or a test fixes it.
    @Entry var workoutTimeline = WorkoutTimeline.live
}
