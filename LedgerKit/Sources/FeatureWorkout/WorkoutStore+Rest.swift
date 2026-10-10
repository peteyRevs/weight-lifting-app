import Foundation
import LedgerDomain

/// The rest and the haptics of `WorkoutStore` (F10 S6): the rest on screen, its time, the haptic at its
/// end, and the playing of an update's haptics. In a file of its own for its length; the members of the
/// store it uses are the store's alone.
///
/// **The rest's time** (F10 S6; ADR-004, the clock rule). The store counts nothing. `moment` is the
/// injected date as it was last read: for each tap the pump plans (the moment a logged set is done at, and
/// "+30s" is tapped at, so a rest is first drawn at its own start), and, while a rest is shown, at each
/// second of that rest (`keepRestTime()`, which waits on the injected clock and then reads the date
/// again). The panel is the presentation's reading of the rest at that moment, so after any time away it
/// shows the wall clock's time left as soon as the wait ends. The date is read nowhere else: not at an
/// update of the session, whose order among the taps is not fixed.
extension WorkoutStore {
    /// Plays the haptics of one update, in order. Only `follow()` calls it.
    func play(_ changes: [Haptic]) async {
        for haptic in changes {
            await haptics.play(haptic)
        }
    }

    /// The rest on screen, which `WorkoutRoot` runs `keepRestTime()` for: nil while no workout is shown,
    /// and while the workout shows no rest.
    var shownRest: RestTimer? {
        if case let .loaded(state) = workout {
            return state.shownRest
        }
        return nil
    }

    /// Keeps the shown rest's time for as long as it runs: reads the injected date into `moment`, waits on
    /// the injected clock until the time left next reads differently (`RestTimer.nextTick(after:)`: the
    /// rest's next whole second), and reads the date again. `WorkoutRoot` runs it again whenever the shown
    /// rest changes, which ends the wait for the rest before. It ends when the rest is over; "Rest over"
    /// then stands until the workout changes.
    ///
    /// At zero it plays `.restOver` (brief criterion 6), once for each rest, and only when it saw the rest
    /// run and its last wait ended within `restOverWindow` of the rest's end. So a rest that had already
    /// ended when it began is not played (a cover opened again, a task started again), and neither is one
    /// that ended while the app was suspended and whose wait ends on its return: that moment is the
    /// notification's (F23), not a buzz minutes late. A rest that was skipped, extended or replaced by the
    /// next set's is not played either: its wait was cancelled.
    ///
    /// A date that stands still while the clock runs is a test's or a preview's fixed date: there is
    /// nothing to keep, and it ends rather than wait on a rest that never gets shorter.
    func keepRestTime() async {
        guard let rest = shownRest else {
            return
        }
        var sawItRun = false
        while true {
            let now = date.now
            if moment != now {
                moment = now
            }
            guard let wait = rest.nextTick(after: now) else {
                let isOnTime = now.timeIntervalSince(rest.endsAt) < Self.restOverWindow
                if sawItRun, isOnTime, rest != restPlayedOver {
                    restPlayedOver = rest
                    await haptics.play(.restOver)
                }
                return
            }
            guard await (try? clock.sleep(for: wait)) != nil, rest == shownRest, date.now != now else {
                return
            }
            sawItRun = true
        }
    }

    /// How long after a rest's end, in seconds, its last wait may end and its haptic still be played: a
    /// main actor that was busy wakes a little late; an app that was suspended wakes much later.
    static let restOverWindow: TimeInterval = 1
}
