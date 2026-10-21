import Foundation
import ObjectiveC
import Observation
import Synchronization

// F08 S2 adversarial round 1: how the tester's suites wait. Every wait is for an event (a call arriving, a store
// changing, an object going away), never for time, and every wait ends when its test is cancelled.

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6): the PR lane and
/// `swift test` run a representative part of the tester's larger matrices and seed ranges, the nightly lane all.
nonisolated enum AdversarialLane {
    static let isNightly = ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    /// The nightly lane, or a run by hand that asks for the whole of a matrix (`LEDGER_ADVERSARIAL_FULL=1`; for
    /// `xcodebuild`, `TEST_RUNNER_LEDGER_ADVERSARIAL_FULL=1`): a test plan sets its own lane.
    static let runsEverything = isNightly || ProcessInfo.processInfo.environment["LEDGER_ADVERSARIAL_FULL"] == "1"
}

/// One wait of a test: it ends when it is woken, or when its task is cancelled, so a wait for something that
/// never happens fails its test at the suite's time limit instead of hanging the run.
final nonisolated class Waiter: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var isWoken = false
    }

    private let state = Mutex(State())

    func wake() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isWoken = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }

    /// Suspends until `wake()` or the task's cancellation, whichever is first; at once if already woken.
    func sleep() async {
        await withTaskCancellationHandler {
            await sleepThroughCancellation()
        } onCancel: {
            wake()
        }
    }

    /// Suspends until `wake()`, whatever happens to the task: how a store call that ignores cancellation waits.
    func sleepThroughCancellation() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isWoken = state.withLock { state -> Bool in
                if state.isWoken {
                    return true
                }
                state.continuation = continuation
                return false
            }
            if isWoken {
                continuation.resume()
            }
        }
    }
}

/// Suspends until `condition` holds, woken by the observation of what it reads (an `@Observable` store's state):
/// no sleep, no polling. Cancelled, it returns with the condition unmet, which the test's expectations then show.
@MainActor
func observed(until condition: @MainActor () -> Bool) async {
    while !condition(), !Task.isCancelled {
        let waiter = Waiter()
        withObservationTracking {
            _ = condition()
        } onChange: {
            waiter.wake()
        }
        await waiter.sleep()
    }
}

/// Tells a test when an object has been deallocated: an associated token whose own deinit wakes the wait.
final nonisolated class DeinitSignal: Sendable {
    private final class Token: Sendable {
        let waiter: Waiter

        init(_ waiter: Waiter) {
            self.waiter = waiter
        }

        deinit {
            waiter.wake()
        }
    }

    /// The association's key: the address of one byte that is never freed, kept as a number (a pointer is not
    /// `Sendable`).
    private static let key = Int(bitPattern: UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    private let waiter = Waiter()

    func watch(_ object: AnyObject) {
        guard let address = UnsafeRawPointer(bitPattern: Self.key) else {
            return
        }
        objc_setAssociatedObject(object, address, Token(waiter), .OBJC_ASSOCIATION_RETAIN)
    }

    /// Returns once the watched object is gone, or when the test is cancelled at its time limit.
    func wait() async {
        await waiter.sleep()
    }
}
