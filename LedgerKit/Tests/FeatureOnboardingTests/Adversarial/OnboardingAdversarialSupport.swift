import Dependencies
@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

// F08 S2 adversarial round 1: what the tester's suites share. Written from the brief's S2 criteria and the
// module's declarations, before reading the slice's own tests.

/// A failure a test plants in a store. Its description carries a word a log reader can look for.
nonisolated struct PlantedFailure: Error, Equatable, CustomStringConvertible {
    let marker: String

    var description: String {
        "planted failure \(marker)"
    }
}

/// A point where a test holds an asynchronous call and lets it go later: no sleep, no polling.
final nonisolated class Checkpoint: Sendable {
    private struct State {
        var isOpen: Bool
        var arrivals = 0
        var cancellations = 0
        var held: [Waiter] = []
        var arrivalWatchers: [(count: Int, waiter: Waiter)] = []
        var cancellationWatchers: [Waiter] = []
    }

    private let state: Mutex<State>

    init(open: Bool = false) {
        state = Mutex(State(isOpen: open))
    }

    /// Reports the arrival, then waits until the checkpoint is open, whatever happens to the task.
    func pass() async {
        await arrive().sleepThroughCancellation()
    }

    /// Reports the arrival, then waits until the checkpoint is open or the calling task is cancelled, as a
    /// store call that gives up on cancellation does. Returns whether it was cancelled.
    func passUnlessCancelled() async -> Bool {
        let held = arrive()
        await held.sleep()
        guard Task.isCancelled else {
            return false
        }
        let watchers = state.withLock { state -> [Waiter] in
            state.cancellations += 1
            defer { state.cancellationWatchers = [] }
            return state.cancellationWatchers
        }
        watchers.forEach { $0.wake() }
        return true
    }

    private func arrive() -> Waiter {
        let held = Waiter()
        let wake = state.withLock { state -> [Waiter] in
            state.arrivals += 1
            var wake = state.arrivalWatchers.filter { $0.count <= state.arrivals }.map(\.waiter)
            state.arrivalWatchers.removeAll { $0.count <= state.arrivals }
            if state.isOpen {
                wake.append(held)
            } else {
                state.held.append(held)
            }
            return wake
        }
        wake.forEach { $0.wake() }
        return held
    }

    /// Lets every held call go, and every later one straight through.
    func open() {
        let held = state.withLock { state -> [Waiter] in
            state.isOpen = true
            defer { state.held = [] }
            return state.held
        }
        held.forEach { $0.wake() }
    }

    /// Returns once `count` calls have arrived, held or not.
    func arrivals(_ count: Int = 1) async {
        let waiter = Waiter()
        let isReached = state.withLock { state -> Bool in
            if state.arrivals >= count {
                return true
            }
            state.arrivalWatchers.append((count, waiter))
            return false
        }
        if isReached {
            waiter.wake()
        }
        await waiter.sleep()
    }

    /// Returns once a call held by `passUnlessCancelled()` has seen its task cancelled.
    func cancellation() async {
        let waiter = Waiter()
        let isReached = state.withLock { state -> Bool in
            if state.cancellations > 0 {
                return true
            }
            state.cancellationWatchers.append(waiter)
            return false
        }
        if isReached {
            waiter.wake()
        }
        await waiter.sleep()
    }

    var arrived: Int {
        state.withLock { $0.arrivals }
    }
}

/// What happened across the stores and the retry step of one scene, in order.
final nonisolated class Journal: Sendable {
    private let entries = Mutex<[String]>([])

    func note(_ entry: String) {
        entries.withLock { $0.append(entry) }
    }

    var all: [String] {
        entries.withLock { $0 }
    }

    func count(of entry: String) -> Int {
        all.count { $0 == entry }
    }
}

/// How one call of a probed store goes.
nonisolated struct CallPlan: Sendable {
    enum Outcome: Sendable {
        case pass
        case fail(PlantedFailure)
        /// Throws `CancellationError` whether or not the task is cancelled.
        case cancellation
        /// Throws `CancellationError` if the task was cancelled while the call was held, as GRDB's writes do.
        case honourCancellation
    }

    /// How the call waits at its checkpoint.
    enum Hold: Sendable {
        /// Until the checkpoint opens, whatever happens to the task.
        case untilOpen
        /// Until the checkpoint opens or the task is cancelled; cancelled, the call throws `CancellationError`.
        case untilOpenOrCancelled
    }

    var checkpoint: Checkpoint?
    var hold = Hold.untilOpen
    var outcome = Outcome.pass

    static let pass = CallPlan()

    static func fail(_ marker: String) -> CallPlan {
        CallPlan(outcome: .fail(PlantedFailure(marker: marker)))
    }

    static func hold(_ checkpoint: Checkpoint, then outcome: Outcome = .pass) -> CallPlan {
        CallPlan(checkpoint: checkpoint, outcome: outcome)
    }

    static func holdUnlessCancelled(_ checkpoint: Checkpoint) -> CallPlan {
        CallPlan(checkpoint: checkpoint, hold: .untilOpenOrCancelled)
    }
}

/// The plans of one probed call site: the queued ones in order, then `otherwise`. With a `Stepper` attached,
/// every call waits for the test to release it instead, with the outcome the test then names.
final nonisolated class CallScript: Sendable {
    private let queued = Mutex<[CallPlan]>([])
    private let fallback = Mutex(CallPlan.pass)
    private let stepper = Mutex<Stepper?>(nil)

    func next(_ plans: CallPlan...) {
        queued.withLock { $0.append(contentsOf: plans) }
    }

    func otherwise(_ plan: CallPlan) {
        fallback.withLock { $0 = plan }
    }

    func step(with stepper: Stepper) {
        self.stepper.withLock { $0 = stepper }
    }

    /// Notes the call, waits at its checkpoint (or for its release) and throws what its outcome says.
    func run(_ name: String, in journal: Journal) async throws {
        journal.note(name)
        let outcome: CallPlan.Outcome
        if let stepped = stepper.withLock({ $0 }) {
            outcome = await stepped.arrive(name)
        } else {
            let plan = queued.withLock { $0.isEmpty ? nil : $0.removeFirst() } ?? fallback.withLock { $0 }
            switch plan.hold {
            case .untilOpen:
                await plan.checkpoint?.pass()
                outcome = plan.outcome
            case .untilOpenOrCancelled:
                let isCancelled = await plan.checkpoint?.passUnlessCancelled() ?? false
                outcome = isCancelled ? .cancellation : plan.outcome
            }
        }
        switch outcome {
        case .pass: break
        case let .fail(failure): throw failure
        case .cancellation: throw CancellationError()
        case .honourCancellation: try Task.checkCancellation()
        }
    }
}
