import Foundation
import LedgerDomain
import Synchronization

/// A session host's three stores seen from outside (F10 S2): every call the host makes is recorded, can be
/// made to suspend, to wait or to throw, and is then passed on to the real store. A host awaits its store,
/// and an actor lets another call in at every `await`; a hop to an idle in-memory store lets nobody in. So a
/// host is run over stores that give way inside every call (`yields`), where an `await` between a check and
/// its commit is a point another caller does reach.
public actor StoreProbe {
    /// A store call a session host makes, or the one a program builder makes (`updateProgram`, F11 S3).
    public enum Call: String, Sendable, CaseIterable {
        case append, envelopes, unreadableCount, highestSeq, uncompactedWorkoutIDs, newestWallClock, compact
        case materialize, activeProgram
        case updateProgram
    }

    /// What a call made to fail throws.
    public struct Refusal: Error, Equatable, Sendable {
        public let call: Call

        public init(call: Call) {
            self.call = call
        }
    }

    /// What `waitUntilHeld()` throws when its task is cancelled, as a suite's time limit does, before the
    /// held call was made: the host took a path on which that call never comes.
    public struct NeverHeld: Error, Equatable, Sendable, CustomStringConvertible {
        /// The call that was held, or nil when none was.
        public let call: Call?

        public init(call: Call?) {
            self.call = call
        }

        public var description: String {
            "the host never made the held store call (\(call?.rawValue ?? "none was held")): nothing to wait for"
        }
    }

    private struct Fault {
        var times: Int
        let afterStoring: Bool
    }

    /// Every call made, in order.
    public private(set) var calls: [Call] = []
    /// What `unreadableCount(for:)` answers in place of the store, when set.
    private var unreadable: Int?
    private var faults: [Call: Fault] = [:]
    private var held: Call?
    private var parked: CheckedContinuation<Void, Never>?
    /// Those waiting in `waitUntilHeld()`, by the order they came. Behind a lock, not the actor, so that a
    /// cancelled waiter is let go from its cancellation handler, which cannot wait for the actor.
    private let arrivals = Mutex<[Int: Arrival]>([:])
    private var nextArrival = 0

    /// One caller of `waitUntilHeld()`: waiting, or cancelled before it could wait.
    private enum Arrival {
        case waiting(CheckedContinuation<Void, Never>)
        case cancelled
    }

    public init() {}

    /// The next `times` calls of `call` throw `Refusal`: before reaching the store, or, with `afterStoring`,
    /// once the store has done what was asked (an acknowledgement that is lost).
    public func fail(_ call: Call, times: Int = 1, afterStoring: Bool = false) {
        faults[call] = Fault(times: times, afterStoring: afterStoring)
    }

    /// No call fails any more.
    public func heal() {
        faults = [:]
    }

    /// Forgets the calls recorded so far.
    public func clearCalls() {
        calls = []
    }

    /// Every log reads as holding `count` rows this version cannot read; `nil` asks the store again.
    public func pretendUnreadable(_ count: Int?) {
        unreadable = count
    }

    /// The next `call` waits inside the store until `release()`.
    public func hold(_ call: Call) {
        held = call
    }

    /// Returns once a held call is waiting. Throws `NeverHeld` when the waiting task is cancelled first, so a
    /// test whose host never makes the held call fails at its time limit with that message, and does not
    /// wait for ever.
    public func waitUntilHeld() async throws {
        guard parked == nil else {
            return
        }
        let arrival = nextArrival
        nextArrival += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting in
                let wasCancelled = arrivals.withLock { arrivals in
                    guard arrivals[arrival] == nil else {
                        return true
                    }
                    arrivals[arrival] = .waiting(waiting)
                    return false
                }
                if wasCancelled {
                    waiting.resume()
                }
            }
        } onCancel: {
            let before = arrivals.withLock { $0.updateValue(.cancelled, forKey: arrival) }
            if case let .waiting(waiting) = before {
                waiting.resume()
            }
        }
        guard parked != nil else {
            throw NeverHeld(call: held)
        }
    }

    /// Lets the waiting call go on.
    public func release() {
        parked?.resume()
        parked = nil
    }

    func unreadableOverride() -> Int? {
        unreadable
    }

    /// Before the store: records the call, parks it when it is held, and throws when it is made to fail.
    func enter(_ call: Call) async throws {
        calls.append(call)
        if held == call {
            held = nil
            await withCheckedContinuation { waiting in
                parked = waiting
                let arrived = arrivals.withLock { arrivals in
                    defer { arrivals = [:] }
                    return Array(arrivals.values)
                }
                for case let .waiting(waiter) in arrived {
                    waiter.resume()
                }
            }
        }
        try refuse(call, afterStoring: false)
    }

    /// After the store: throws when the call is made to fail once it is stored.
    func leave(_ call: Call) throws {
        try refuse(call, afterStoring: true)
    }

    private func refuse(_ call: Call, afterStoring: Bool) throws {
        guard let fault = faults[call], fault.afterStoring == afterStoring, fault.times > 0 else {
            return
        }
        faults[call]?.times -= 1
        throw Refusal(call: call)
    }
}
