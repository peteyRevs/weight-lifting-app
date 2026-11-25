import Foundation
import LedgerDomain

/// A start the phone asks the watch for (F17 S5a, criterion 8): the phone stores its `started`, sends it, and asks
/// the watch to start (`requestWatchStart()`), which the watch reports as `.startRequestedByPhone`. The watch adopts
/// the phone's workout when its `started` arrives within `phoneStartWait` (the receipt makes it the live one, S3);
/// otherwise it starts its own. Two workouts live at once are both kept, on both devices, as S3 keeps them: which
/// one goes on is S5b's (pending Pete), and nothing here drops a log.
public extension LocalWorkoutSessionActor {
    /// How long the watch waits for the phone's `started` after the phone asked it to start.
    static let phoneStartWait = Duration.seconds(5)

    /// Whether a workout is live within `phoneStartWait` on `clock`: at once when one is (the phone's arrived
    /// first, or the lifter already started one here), or as soon as one becomes live. False when the wait ends
    /// first, or the caller's task is cancelled.
    nonisolated func adoptsPhoneStart(clock: any Clock<Duration> = ContinuousClock()) async -> Bool {
        let updates = await updates()
        let wait = Self.phoneStartWait
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await update in updates where update.state?.phase == .live {
                    return true
                }
                return false
            }
            group.addTask {
                try? await clock.sleep(for: wait)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// The watch's answer to each `.startRequestedByPhone` in `events` (its own subscription to
    /// `HealthEventBroadcast`), in turn: the phone's workout when it is live within `phoneStartWait`, else
    /// `startOwn` (the screen's start of its cached day, F18/F19). Every other event is ignored. Returns when
    /// `events` ends or the caller's task is cancelled, and never starts a workout after it was cancelled.
    nonisolated func followPhoneStartRequests(
        _ events: AsyncStream<HealthSessionEvent>,
        clock: any Clock<Duration> = ContinuousClock(),
        startOwn: @escaping @Sendable () async -> Void
    ) async {
        for await event in events where event == .startRequestedByPhone {
            let adopted = await adoptsPhoneStart(clock: clock)
            guard !adopted, !Task.isCancelled else {
                continue
            }
            logger.notice("The phone's workout did not arrive within 5 s; starting our own")
            await startOwn()
        }
    }
}
