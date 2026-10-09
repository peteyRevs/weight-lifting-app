import Foundation
import LedgerDomain

/// What `TodayStore` knows of its sources during one `run()`: the last value of each of the five it follows,
/// and the two plain reads (`TodayHistory`) as long as nothing they depend on has changed.
nonisolated struct TodaySources {
    /// Each is nil until the source's first value. The program and the session's workout are themselves
    /// optional: `.some(nil)` is "none", known.
    var program: Program??
    var settings: Settings?
    var exercises: [ExerciseID: Exercise]?
    var recentWorkouts: [WorkoutState]?
    var session: WorkoutState??
    /// A store's observation ended by itself: the model can no longer follow it.
    var hasEnded = false

    /// The plain reads as they were last made; nil when a source they depend on has changed since.
    private(set) var history: TodayHistory?
    /// Counts the changes that made `history` stale, so that a read one of them overtook is not kept.
    private(set) var staleCount = 0

    /// A source the plain reads depend on has changed: they are made again before the next model.
    mutating func forgetHistory() {
        history = nil
        staleCount += 1
    }

    /// Keeps `read`, unless a change has made it stale since `count` was taken, before the read began. That
    /// change has marked the store's channel too, so its next turn reads again.
    mutating func keep(_ read: TodayHistory, readSince count: Int) {
        if staleCount == count {
            history = read
        }
    }

    /// The five sources' values, once every one of them has spoken.
    struct Known {
        let program: Program?
        let settings: Settings
        let exercises: [ExerciseID: Exercise]
        let recentWorkouts: [WorkoutState]
        let session: WorkoutState?

        /// What the presentation is handed: these values, `history`, and the moment and its calendar.
        func input(_ history: TodayHistory, now: Date, calendar: Calendar, locale: Locale) -> TodayInput {
            TodayInput(
                program: program,
                exercises: exercises,
                settings: settings,
                weekWorkouts: history.weekWorkouts,
                recentWorkouts: recentWorkouts,
                previousWeekVolume: history.previousWeekVolume,
                session: session,
                now: now,
                calendar: calendar,
                locale: locale
            )
        }
    }

    var known: Known? {
        guard let program, let settings, let exercises, let recentWorkouts, let session else {
            return nil
        }
        return Known(
            program: program,
            settings: settings,
            exercises: exercises,
            recentWorkouts: recentWorkouts,
            session: session
        )
    }
}
