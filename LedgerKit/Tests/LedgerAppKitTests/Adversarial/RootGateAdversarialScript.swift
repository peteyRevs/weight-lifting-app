import Foundation
@testable import LedgerAppKit
import LedgerDomain
import Synchronization

// F08 S3 adversarial round 1 (G2): a store of programs and a launch that the test moves by hand, one event at a
// time, so every order of the launch's pass, the store's answers, a stream's end and a cancelled call can be
// played, and the gate is read between any two events.

/// One stream of `observeActive()`, fed by the test. It counts each time its consumer asks for the next value:
/// a consumer that asks again has finished with the value before.
final nonisolated class GateFeed: Sendable {
    private enum Item {
        case value(Program?)
        case end
    }

    private struct State {
        var pending: [Item] = []
        var consumer: CheckedContinuation<Program??, Never>?
        var requests = 0
        var isCancelled = false
        var waiters: [GateWaiter] = []
    }

    private let state = Mutex(State())

    /// How many times the consumer has asked for a value.
    var requests: Int {
        state.withLock(\.requests)
    }

    func yield(_ program: Program?) {
        put(.value(program))
    }

    /// Ends the stream on a task nobody cancelled: the active program could not be read.
    func finish() {
        put(.end)
    }

    /// Suspends until the consumer has asked `count` times.
    func requested(_ count: Int) async {
        while !Task.isCancelled {
            let waiter = GateWaiter()
            let isMet = state.withLock { state -> Bool in
                if state.requests >= count {
                    return true
                }
                state.waiters.append(waiter)
                return false
            }
            if isMet {
                return
            }
            await waiter.sleep()
        }
    }

    /// The stream's `unfolding`: the next value, or nil when the stream ends or the consumer's task is cancelled
    /// (an `AsyncStream` ends for a cancelled consumer, as GRDB's bridge and the fake's do).
    func next() async -> Program?? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let (ready, waiters) = state.withLock { state -> (Item?, [GateWaiter]) in
                    state.requests += 1
                    defer { state.waiters = [] }
                    if state.isCancelled {
                        return (.end, state.waiters)
                    }
                    guard !state.pending.isEmpty else {
                        state.consumer = continuation
                        return (nil, state.waiters)
                    }
                    return (state.pending.removeFirst(), state.waiters)
                }
                for waiter in waiters {
                    waiter.wake()
                }
                if let ready {
                    continuation.resume(returning: Self.element(ready))
                }
            }
        } onCancel: {
            let consumer = state.withLock { state -> CheckedContinuation<Program??, Never>? in
                state.isCancelled = true
                defer { state.consumer = nil }
                return state.consumer
            }
            consumer?.resume(returning: nil)
        }
    }

    private func put(_ item: Item) {
        let consumer = state.withLock { state -> CheckedContinuation<Program??, Never>? in
            guard let consumer = state.consumer else {
                state.pending.append(item)
                return nil
            }
            state.consumer = nil
            return consumer
        }
        consumer?.resume(returning: Self.element(item))
    }

    private static func element(_ item: Item) -> Program?? {
        switch item {
        case let .value(program): .some(program)
        case .end: nil
        }
    }
}

/// A store of programs whose streams the test feeds. It notes every call it receives: the gate may observe, and
/// nothing else.
final nonisolated class GateScriptedPrograms: ProgramRepository {
    private let feeds = Mutex<[GateFeed]>([])
    let journal = GateJournal()

    /// How many times `observeActive()` was called.
    var subscriptions: Int {
        feeds.withLock(\.count)
    }

    func feed(_ index: Int) -> GateFeed? {
        feeds.withLock { $0.indices.contains(index) ? $0[index] : nil }
    }

    func active() async throws -> Program? {
        journal.note("active")
        return nil
    }

    func save(_: Program) async throws {
        journal.note("save")
    }

    func setActive(_: ProgramID) async throws {
        journal.note("setActive")
    }

    func delete(_: ProgramID) async throws {
        journal.note("delete")
    }

    func observeActive() -> AsyncStream<Program?> {
        let feed = GateFeed()
        let index = feeds.withLock { feeds -> Int in
            feeds.append(feed)
            return feeds.count - 1
        }
        journal.note("subscribe \(index)")
        return AsyncStream(unfolding: { await feed.next() })
    }
}

/// One call of `RootGate.follow(after:)`, as the root's `.task(id: scenePhase)` makes it: its launch waits until
/// the test lets the pass return, and ignores cancellation, as `DatabaseLaunch.resume` does.
final class GateScriptedCall {
    enum Phase: Equatable {
        case launching
        case following(feed: Int)
        case ended
    }

    let entered = GateWaiter()
    let pass = GateWaiter()
    private(set) var launches = 0
    private(set) var task: Task<Void, Never>?
    var answer: (any ProgramRepository)?
    var phase = Phase.launching
    var isCancelled = false
    /// Whether the launch returned an open store to a call nobody had cancelled: the call then observes it.
    var hasFollowed = false

    /// Starts the call on `gate` and returns once the gate is waiting for the launch.
    func start(on gate: RootGate) async {
        task = Task {
            await gate.follow {
                self.launches += 1
                self.entered.wake()
                await self.pass.sleepThroughCancellation()
                return self.answer
            }
        }
        await entered.sleep()
    }

    func cancel() {
        isCancelled = true
        task?.cancel()
    }

    /// Lets the launch's pass return `answer`.
    func returnLaunch(_ answer: (any ProgramRepository)?) {
        self.answer = answer
        pass.wake()
    }

    /// Suspends until the call has returned.
    func finished() async {
        await task?.value
    }
}

/// What the root must show, as the specification says it (brief, S3 criteria 1 to 4; the plan's gate risks):
/// nothing is decided before the launch's pass has returned an open store; then each value the store reports
/// decides; a stream that ends on a task nobody cancelled is a program that cannot be read, and shows the tabs;
/// a cancelled call changes nothing.
nonisolated struct GateModel {
    private(set) var destination = RootGate.Destination.loading
    private(set) var history: [RootGate.Destination] = [.loading]

    mutating func reported(_ program: Program?) {
        show(program == nil ? .onboarding : .main)
    }

    mutating func streamEnded() {
        show(.main)
    }

    private mutating func show(_ next: RootGate.Destination) {
        if next != destination {
            destination = next
            history.append(next)
        }
    }
}
