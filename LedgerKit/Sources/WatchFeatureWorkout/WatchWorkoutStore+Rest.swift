import Foundation
import LedgerDomain

/// The end of the watch's rest (F18 criteria 6, 7 and 15): the edges where the mode moves by time alone, and the buzz.
///
/// **Time.** The mode is a function of the date (`WatchMode(_:at:summaryDismissed:)`), and the date changes no
/// observed value, so the store keeps one task for the shown rest (`keepRest`) that wakes at its edges, the rest's end
/// (rest → "GO") and `goWindow` after it ("GO" → ready), and moves `restEdges` there, which `now` reads: a screen that
/// draws the mode draws it again at each edge, and nothing polls.
///
/// **From the date to the clock.** `endsAt` is a wall-clock `Date`, often the phone's; the injected `continuousClock`
/// has no epoch, so a deadline is never carried from one to the other. The task reads the date, sleeps on the clock
/// for what is left (`endsAt − date`), which counts on while the watch's screen is off, and reads the date again: a
/// wall clock that moved more slowly (a time sync during the rest) is waited out again, and the end is the date's,
/// never the clock's count. A date that stands still while the clock runs is a test's or a preview's fixed date, and
/// the task ends rather than wait on a rest that never gets shorter, as the phone's `keepRestTime()` does.
///
/// **The buzz.** At the end the rest-over haptic plays when `Settings.watchBuzz` is on (spec §4.5), and only when the
/// task saw the rest run and woke within `goWindow` of its end: a rest already over when it was first shown, or one
/// whose end the watch slept through, is not felt late, as on the phone. The screens are the same with the buzz on or
/// off (D11): only the haptic is gated. Reduce Motion changes the screen's shake, never this (criterion 15).
///
/// **One task.** The rest's task is replaced whenever the shown rest changes: "Skip" (no rest), "+30s" (a new
/// `endsAt`, also at zero, where it is a new 30 s rest), the next set's rest, another workout, the end of the workout
/// (finish or discard). Replacing it cancels its sleep, so a rest that is not shown any more never buzzes.
extension WatchWorkoutStore {
    /// The date as the screens read it: the injected date, observed through `restEdges` so that the mode is read again
    /// at the rest's edges.
    var now: Date {
        _ = restEdges
        return date.now
    }

    /// Follows the shown rest after a change of the workout: a rest it is not following yet gets a task of its own in
    /// place of the one before.
    func followRest() {
        let shown = live?.shownRest
        guard shown != followedRest else {
            return
        }
        followedRest = shown
        restTask?.cancel()
        restTask = shown.map { rest in Task { await self.keepRest(rest) } }
    }

    /// Stops following the rest: the root's task has ended, and with it the session's stream.
    func stopFollowingRest() {
        restTask?.cancel()
        restTask = nil
        followedRest = nil
    }

    /// Waits for `rest`'s end, moves the screen to "GO" there (buzzing, when it should), and to ready `goWindow` later.
    private func keepRest(_ rest: RestTimer) async {
        var moment = date.now
        var sawItRun = false
        while moment < rest.endsAt {
            guard await (try? clock.sleep(for: .seconds(rest.endsAt.timeIntervalSince(moment)))) != nil else {
                return
            }
            let woke = date.now
            guard woke != moment else {
                return
            }
            (moment, sawItRun) = (woke, true)
        }
        if sawItRun {
            restEdges += 1
        }
        let late = Duration.seconds(moment.timeIntervalSince(rest.endsAt))
        guard late < WatchMode.goWindow else {
            return
        }
        if sawItRun, (settings ?? .default).watchBuzz {
            haptic.enqueue([.restOver])
        }
        guard await (try? clock.sleep(for: WatchMode.goWindow - late)) != nil else {
            return
        }
        restEdges += 1
    }
}
