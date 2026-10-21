import Foundation
import Synchronization

// F08 S2 adversarial round 1: the stepper behind the random interleavings (`SteppedRoot`).

/// Runs tasks one probed call at a time: each call waits here until the test releases it, and the test can wait
/// until every task it started is either waiting here or has ended. No sleep, no polling.
final nonisolated class Stepper: Sendable {
    private struct State {
        var running = 0
        var waiting: [(name: String, resume: CheckedContinuation<CallPlan.Outcome, Never>)] = []
        var settlers: [Waiter] = []

        mutating func takeSettlersIfQuiet() -> [Waiter] {
            guard running == 0 else {
                return []
            }
            defer { settlers = [] }
            return settlers
        }
    }

    private let state = Mutex(State())

    /// The calls waiting to be released, oldest first.
    var waiting: [String] {
        state.withLock { $0.waiting.map(\.name) }
    }

    func taskStarted() {
        state.withLock { $0.running += 1 }
    }

    func taskEnded() {
        let wake = state.withLock { state -> [Waiter] in
            state.running -= 1
            return state.takeSettlersIfQuiet()
        }
        wake.forEach { $0.wake() }
    }

    /// A probed call of a started task waits here, and returns the outcome it is released with.
    func arrive(_ name: String) async -> CallPlan.Outcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<CallPlan.Outcome, Never>) in
            let wake = state.withLock { state -> [Waiter] in
                state.waiting.append((name, continuation))
                state.running -= 1
                return state.takeSettlersIfQuiet()
            }
            wake.forEach { $0.wake() }
        }
    }

    /// Releases the oldest waiting call with `outcome`, and returns its name; nil when none waits.
    @discardableResult
    func release(_ outcome: CallPlan.Outcome) -> String? {
        let call = state.withLock { state -> (name: String, resume: CheckedContinuation<CallPlan.Outcome, Never>)? in
            guard !state.waiting.isEmpty else {
                return nil
            }
            state.running += 1
            return state.waiting.removeFirst()
        }
        call?.resume.resume(returning: outcome)
        return call?.name
    }

    /// Returns once no started task is running: each waits at a call or has ended.
    func settle() async {
        let waiter = Waiter()
        let isQuiet = state.withLock { state -> Bool in
            if state.running == 0 {
                return true
            }
            state.settlers.append(waiter)
            return false
        }
        if isQuiet {
            waiter.wake()
        }
        await waiter.sleep()
    }
}
