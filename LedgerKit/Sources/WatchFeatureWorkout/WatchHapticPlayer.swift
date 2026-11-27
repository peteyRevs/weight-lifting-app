import Foundation
import LedgerDomain

/// The watch's three haptics (F18 "Haptics"; R1 §5.3), as `WKInterfaceDevice.play(_:)` names them: a logged set is a
/// click, the end of a rest the notification pattern, a new record success. A finished workout plays none on the wrist
/// (orchestrator ruling 3): the summary says it, and the brief allows these three alone.
public nonisolated enum WatchHapticPattern: Equatable, Sendable {
    case click, notification, success

    /// The pattern `haptic` plays on the watch; nil for one it does not play.
    public init?(_ haptic: Haptic) {
        switch haptic {
        case .setLogged: self = .click
        case .restOver: self = .notification
        case .personalRecord: self = .success
        case .workoutFinished: return nil
        }
    }
}

/// Plays the watch's haptics through the injected client in the order they came, each at least `spacing` after the
/// one before (R1 §5.3: the Taptic Engine runs one pattern at a time, and HR sampling pauses while it does). A haptic
/// that comes too soon waits its turn rather than being dropped: they come one or two to a change, and each says
/// something a lifter not looking at the wrist should feel. One the watch does not play (`WatchHapticPattern`) is never
/// queued, so it takes no turn. `run` is a task of the store's `run()`, for as long as that runs.
@MainActor
final class WatchHapticPlayer {
    static let spacing: Duration = .milliseconds(100)

    /// The haptics waiting to be played, oldest first.
    private(set) var queue: [Haptic] = []
    private var wake: AsyncStream<Void>.Continuation?

    func enqueue(_ haptics: [Haptic]) {
        let played = haptics.filter { WatchHapticPattern($0) != nil }
        guard !played.isEmpty else {
            return
        }
        queue += played
        wake?.yield()
    }

    /// Plays each waiting haptic, then waits `spacing` on `clock` before the next, until its task is cancelled.
    func run(haptics: any HapticsClient, clock: any Clock<Duration>) async {
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        continuation.yield()
        for await _ in signals {
            while !queue.isEmpty {
                await haptics.play(queue.removeFirst())
                guard await (try? clock.sleep(for: Self.spacing)) != nil else {
                    return
                }
            }
        }
    }
}
