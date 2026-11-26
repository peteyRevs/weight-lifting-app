import Foundation
import LedgerDomain

/// Which screen the watch shows (spec §4.2, as F18 resolves §4.5's "GO" edge). The watch derives it from the
/// workout it holds at a moment it is handed; it reads no clock of its own.
nonisolated enum WatchMode: Equatable, Sendable {
    /// No live workout: today's plan.
    case idle
    /// The set to log.
    case ready
    /// The countdown, before `endsAt`.
    case rest(RestTimer)
    /// The rest is over: the rest screen reads "GO" for `goWindow`, then the set screen shows.
    case restOver(RestTimer)
    /// The finished workout, until the lifter taps "Done".
    case summary

    /// How long the rest screen reads "GO" once the rest is over (F18: the buzz's three 0.38 s shakes).
    static let goWindow: Duration = .milliseconds(1200)

    /// The finished workout is the summary until it is dismissed; no live workout is idle. A live workout rests
    /// while the rest it shows (`WorkoutState.shownRest`) has time left, is at "GO" from `endsAt` for `goWindow`,
    /// and is otherwise ready. So a rest that is skipped, or a set logged once it had ended, leaves at once.
    init(_ workout: WorkoutState?, at now: Date, summaryDismissed: Bool) {
        guard let workout, workout.phase == .live else {
            self = workout?.phase == .finished && !summaryDismissed ? .summary : .idle
            return
        }
        guard let rest = workout.shownRest else {
            self = .ready
            return
        }
        if now < rest.endsAt {
            self = .rest(rest)
        } else if now < rest.endsAt.addingTimeInterval(Self.goWindow / .seconds(1)) {
            self = .restOver(rest)
        } else {
            self = .ready
        }
    }

    /// Whether the list and the end overlays may open over this mode (spec §4.2): only while the workout is live.
    var isLive: Bool {
        switch self {
        case .ready, .rest, .restOver: true
        case .idle, .summary: false
        }
    }
}
