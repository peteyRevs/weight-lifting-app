import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The real engine behind a session the test drives by hand (G2, F10 S7a): S5's `PumpSession` with the two
/// ends made as awkward as its changes. Every `apply`, and every `finish` and `discard`, can be made to wait;
/// a `finish` can be made to fail; the stream can be kept behind, its first update included, or ended; and
/// another hand can change or end the workout in between.
///
/// Like a host, an end that was let on is completed whatever became of its caller: a caller cancelled
/// meanwhile is thrown `CancellationError`, and the workout has ended all the same.
actor SaveSession: WorkoutSessionClient {
    nonisolated struct Refused: Error, Equatable {}

    /// One call that changed the workout's log, in the order the engine took them.
    nonisolated enum Reached: Equatable, Sendable {
        case change(WorkoutEvent)
        case finished(Date)
        case discarded(Date)
    }

    private struct Subscriber {
        let continuation: AsyncStream<WorkoutSessionUpdate>.Continuation
        var behind: [WorkoutSessionUpdate] = []
    }

    /// What the store's calls changed, in order. Another hand's changes are not listed.
    private(set) var reached: [Reached] = []
    /// The end every `finish` asked for, in call order, whether or not it reached the engine.
    private(set) var finishesAsked: [Date] = []
    private(set) var discardsAsked = 0
    /// True once a `finish` was asked while a `discard` waited, or a `discard` while a `finish` waited.
    private(set) var endsOverlapped = false
    /// The workout as it ended; nil while it is live.
    private(set) var ended: WorkoutState?
    private(set) var streamsOpened = 0
    /// How many `apply` calls wait to be let on: read from the main actor without a hop.
    nonisolated let waiting = LockIsolated(0)
    /// How many `finish` and `discard` calls wait to be let on.
    nonisolated let endsWaiting = LockIsolated(0)
    /// How many times `finish` was asked, read without a hop.
    nonisolated let finishCalls = LockIsolated(0)

    private var live: WorkoutState?
    private var seq: UInt64 = 1
    private var subscribers: [Subscriber] = []
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var parkedEnds: [(isFinish: Bool, call: CheckedContinuation<Void, Never>)] = []
    private var calls = 0
    private var refused: Set<Int> = []
    private var holdsEveryApply = false
    private var holdsEveryEnd = false
    private var isBehind = false
    private var keepsFirstUpdateBehind = false
    private var finishFailures: [any Error] = []

    init(live: WorkoutState) {
        self.live = WorkoutEngine.reduce(nil, Self.envelope(.started(live), in: live.id, seq: 1)).0
    }

    // MARK: WorkoutSessionClient

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
        streamsOpened += 1
        var subscriber = Subscriber(continuation: continuation)
        let first = WorkoutSessionUpdate(state: live)
        if keepsFirstUpdateBehind {
            subscriber.behind.append(first)
        } else {
            continuation.yield(first)
        }
        subscribers.append(subscriber)
        return stream
    }

    func current() -> WorkoutState? {
        live
    }

    func start(_ initial: WorkoutState) throws {
        throw WorkoutSessionError.workoutInProgress(live?.id ?? initial.id)
    }

    @discardableResult
    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        calls += 1
        let number = calls
        if holdsEveryApply {
            waiting.withValue { $0 += 1 }
            await withCheckedContinuation { parked.append($0) }
        }
        if refused.contains(number) {
            throw Refused()
        }
        let answer = try reduce(event)
        reached.append(.change(event))
        return answer
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        finishesAsked.append(endedAt)
        finishCalls.withValue { $0 += 1 }
        await waitAsAnEnd(isFinish: true)
        if !finishFailures.isEmpty {
            throw finishFailures.removeFirst()
        }
        let answer = try reduce(.finished(endedAt: endedAt))
        guard answer.phase == .finished else {
            throw WorkoutSessionError.invalidEndDate
        }
        reached.append(.finished(endedAt))
        try Task.checkCancellation()
        return answer
    }

    func discard(endedAt: Date) async throws {
        discardsAsked += 1
        await waitAsAnEnd(isFinish: false)
        _ = try reduce(.discarded(endedAt: endedAt))
        reached.append(.discarded(endedAt))
        try Task.checkCancellation()
    }

    private func waitAsAnEnd(isFinish: Bool) async {
        if parkedEnds.contains(where: { $0.isFinish != isFinish }) {
            endsOverlapped = true
        }
        guard holdsEveryEnd else {
            return
        }
        endsWaiting.withValue { $0 += 1 }
        await withCheckedContinuation { parkedEnds.append((isFinish, $0)) }
    }

    // MARK: The engine

    private func reduce(_ event: WorkoutEvent) throws -> WorkoutState {
        guard let workout = live else {
            throw WorkoutSessionError.noLiveWorkout
        }
        let (reduced, effects) = WorkoutEngine.reduce(workout, Self.envelope(event, in: workout.id, seq: seq + 1))
        guard let next = reduced, !effects.isEmpty else {
            return workout
        }
        seq += 1
        live = next.phase == .live ? next : nil
        ended = next.phase == .live ? nil : next
        let update = WorkoutSessionUpdate(state: next, haptics: WorkoutSessionUpdate.haptics(from: effects))
        for index in subscribers.indices {
            if isBehind {
                subscribers[index].behind.append(update)
            } else {
                subscribers[index].continuation.yield(update)
            }
        }
        return next
    }

    private static func envelope(_ event: WorkoutEvent, in workout: WorkoutID, seq: UInt64) -> EventEnvelope {
        EventEnvelope(event: event, workoutID: workout, device: Fixtures.deviceID, seq: seq, wallClock: Fixtures.now)
    }
}

// MARK: - What the test sets

extension SaveSession {
    func holdEveryApply(_ holds: Bool = true) {
        holdsEveryApply = holds
    }

    /// Lets the oldest waiting `apply` on.
    func release() {
        guard !parked.isEmpty else {
            return
        }
        waiting.withValue { $0 -= 1 }
        parked.removeFirst().resume()
    }

    /// Every `finish` and `discard` from now on waits, before it reaches the engine, for `releaseEnd()`.
    func holdEveryEnd(_ holds: Bool = true) {
        holdsEveryEnd = holds
    }

    /// Lets the oldest waiting `finish` or `discard` on.
    func releaseEnd() {
        guard !parkedEnds.isEmpty else {
            return
        }
        endsWaiting.withValue { $0 -= 1 }
        parkedEnds.removeFirst().call.resume()
    }

    /// The next `finish` calls throw these, one each, and change nothing.
    func failFinish(with errors: [any Error]) {
        finishFailures += errors
    }

    /// The `apply` calls with these numbers, counted from 1, throw `Refused` and change nothing.
    func refuse(calls numbers: Set<Int>) {
        refused = numbers
    }

    /// The number the next `apply` will have.
    var nextCall: Int {
        calls + 1
    }

    /// While behind, updates are kept from every open stream until `deliver`; with `first`, so is the
    /// first update of a stream opened meanwhile.
    func keepStreamsBehind(_ behind: Bool = true, first: Bool = false) {
        isBehind = behind
        keepsFirstUpdateBehind = behind && first
        if !behind {
            deliver()
        }
    }

    /// Lets the oldest `count` kept updates on, in order.
    func deliver(_ count: Int = .max) {
        for index in subscribers.indices {
            let ready = subscribers[index].behind.prefix(count)
            subscribers[index].behind.removeFirst(ready.count)
            for update in ready {
                subscribers[index].continuation.yield(update)
            }
        }
    }

    /// Ends every open stream, as no host does and the key's stub does.
    func endStreams() {
        for subscriber in subscribers {
            subscriber.continuation.finish()
        }
        subscribers = []
    }

    /// A change, or an end, by another hand: it reaches the engine at once and is not listed in `reached`.
    @discardableResult
    func elsewhere(_ event: WorkoutEvent) throws -> WorkoutState {
        try reduce(event)
    }
}
