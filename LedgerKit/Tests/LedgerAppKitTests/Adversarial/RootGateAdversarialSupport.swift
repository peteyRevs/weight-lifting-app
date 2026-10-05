import Foundation
@testable import LedgerAppKit
import Observation
import Synchronization

// F08 S3 adversarial round 1 (G2): how the tester's gate suites wait and what they record. Every wait is for an
// event (a call arriving, the gate changing, a statement running), never for time, and every wait ends when its
// test is cancelled, so a wait for something that never happens fails at the suite's time limit.

/// One wait of a test: it ends when it is woken, or when its task is cancelled.
final nonisolated class GateWaiter: Sendable {
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

    /// Suspends until `wake()`, whatever happens to the task: how the launch's pass waits (cancelling a caller
    /// of `DatabaseLaunch.resume` cancels no step, and the caller returns only when its steps have an outcome).
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

/// What happened, in order, from any thread: the launch's events, the statements the database ran, the calls a
/// probed store received. A test waits for a condition of the entries.
final nonisolated class GateJournal: Sendable {
    private struct State {
        var entries: [String] = []
        var waiters: [GateWaiter] = []
    }

    private let state = Mutex(State())

    var entries: [String] {
        state.withLock(\.entries)
    }

    func note(_ entry: String) {
        let waiters = state.withLock { state -> [GateWaiter] in
            state.entries.append(entry)
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters {
            waiter.wake()
        }
    }

    func count(_ matches: (String) -> Bool) -> Int {
        entries.count(where: matches)
    }

    func count(of entry: String) -> Int {
        count { $0 == entry }
    }

    /// Suspends until `condition` holds of the entries. Cancelled first, it returns false, which the test's
    /// expectations then show.
    @discardableResult
    func until(_ condition: @Sendable ([String]) -> Bool) async -> Bool {
        while !Task.isCancelled {
            let waiter = GateWaiter()
            let holds = state.withLock { state -> Bool in
                if condition(state.entries) {
                    return true
                }
                state.waiters.append(waiter)
                return false
            }
            if holds {
                return true
            }
            await waiter.sleep()
        }
        return condition(entries)
    }

    /// Suspends until `entry` has been noted `count` times.
    @discardableResult
    func until(_ entry: String, count: Int = 1) async -> Bool {
        await until { entries in entries.count { $0 == entry } >= count }
    }
}

/// Suspends until `condition` holds, woken by the observation of what it reads (the gate's destination, the
/// composition's state): no sleep, no polling. Cancelled, it returns with the condition unmet.
func gateObserved(until condition: @MainActor () -> Bool) async {
    while !condition(), !Task.isCancelled {
        let waiter = GateWaiter()
        withObservationTracking {
            _ = condition()
        } onChange: {
            waiter.wake()
        }
        await waiter.sleep()
    }
}

/// Every value a gate's `destination` has held, in order, from the moment the recorder is made.
///
/// Observation calls back before each change, on the gate's actor, when the property still holds the value it
/// is about to lose. The recorder notes that value and listens again in the same call, so no change is missed,
/// even two with no suspension between them: this is stricter than a screen, which draws at most once a turn.
/// A destination that was never held was never drawn.
final class GateDestinationRecorder {
    private let gate: RootGate
    private var held: [RootGate.Destination] = []

    init(_ gate: RootGate) {
        self.gate = gate
        listen()
    }

    /// The values held so far, the current one last, without repeats in a row.
    var seen: [RootGate.Destination] {
        (held + [gate.destination]).reduce(into: []) { result, next in
            if result.last != next {
                result.append(next)
            }
        }
    }

    private func listen() {
        withObservationTracking {
            _ = gate.destination
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                self?.changing()
            }
        }
    }

    /// The gate is about to change: its destination is still the one it is leaving.
    private func changing() {
        held.append(gate.destination)
        listen()
    }
}

/// SplitMix64, for the seeded orders; every failing case names its seed.
nonisolated struct GateRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
