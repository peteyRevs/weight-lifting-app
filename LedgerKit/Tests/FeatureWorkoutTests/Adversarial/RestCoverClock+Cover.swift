import Foundation
import LedgerTestSupport
import Testing

extension RestCover {
    /// Waits until `condition`, on what the rest's task and the clock do, holds: looked at again each time
    /// the clock registers a sleep or the task ends (`RestCoverClock.wait(within:until:)`), never by polling.
    /// As `eventually`, a wait that has not come in 10 s of the wall clock, or whose task is cancelled (a time
    /// limit), records an issue that names it and returns.
    func keeperWait(
        _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        let limit = Duration.seconds(10)
        switch await clock.wait(within: limit, until: condition) {
        case .held:
            break
        case .cancelled:
            Issue.record("cancelled while waiting for: \(what)", sourceLocation: sourceLocation)
        case .timedOut:
            Issue.record("never came in \(limit): \(what)", sourceLocation: sourceLocation)
        }
    }
}

extension RestCoverClock {
    /// Moves time on by `duration` as `TestClock.advance(by:)` does, a wait at a time: each wait that ends on
    /// the way is woken, and time moves past it only once all `tasks` sleep again or `isDone` holds, where
    /// `TestClock` moves on when its yields run out. A task still awake when time moves would start its next
    /// wait after the jump, which nothing then ends.
    @MainActor
    func run(_ duration: Duration, tasks: Int = 1, until isDone: @MainActor () -> Bool) async {
        let end = now.advanced(by: duration)
        while !isDone(), let due, due <= end {
            advance(to: due)
            await eventually("the woken tasks asleep again, or done") { self.asleep >= tasks || isDone() }
        }
        advance(to: end)
    }
}
