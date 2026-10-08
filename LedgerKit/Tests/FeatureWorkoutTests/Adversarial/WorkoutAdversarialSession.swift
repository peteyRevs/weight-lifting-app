import Foundation
import LedgerDomain

/// A session client seen from outside (G2, F10 S4): every call the launcher and the store make is recorded,
/// can be made to throw before or after it reaches the real client, or to wait inside until released. It
/// decides nothing: what the workout is stays the wrapped client's (the fake, or the host on in-memory
/// stores).
actor AdversarialSession: WorkoutSessionClient {
    nonisolated enum Call: String, Sendable, CaseIterable {
        case updates, current, start, apply, finish, discard
    }

    nonisolated struct Refusal: Error, Equatable, Sendable {
        let call: Call
    }

    private struct Fault {
        var times: Int
        let afterwards: Bool
    }

    /// Every call made, in order.
    private(set) var calls: [Call] = []
    private let base: any WorkoutSessionClient
    private var faults: [Call: Fault] = [:]
    private var held: Call?
    private var parked: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    init(_ base: any WorkoutSessionClient) {
        self.base = base
    }

    /// The next `times` calls of `call` throw `Refusal`: before the client is asked or, with `afterwards`,
    /// once it has done what was asked (an answer that is lost).
    func fail(_ call: Call, times: Int = 1, afterwards: Bool = false) {
        faults[call] = Fault(times: times, afterwards: afterwards)
    }

    func heal() {
        faults = [:]
    }

    func clearCalls() {
        calls = []
    }

    func count(_ call: Call) -> Int {
        calls.count { $0 == call }
    }

    /// The next `call` waits, before it reaches the client, until `release()`.
    func hold(_ call: Call) {
        held = call
    }

    /// Returns once the held call is waiting.
    func waitUntilHeld() async {
        guard parked == nil else {
            return
        }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func release() {
        parked?.resume()
        parked = nil
    }

    private func enter(_ call: Call) async throws {
        calls.append(call)
        if held == call {
            held = nil
            await withCheckedContinuation { waiting in
                parked = waiting
                for arrival in arrivals {
                    arrival.resume()
                }
                arrivals = []
            }
        }
        try refuse(call, afterwards: false)
    }

    private func refuse(_ call: Call, afterwards: Bool) throws {
        guard let fault = faults[call], fault.afterwards == afterwards, fault.times > 0 else {
            return
        }
        faults[call]?.times -= 1
        throw Refusal(call: call)
    }

    // MARK: WorkoutSessionClient

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        calls.append(.updates)
        return await base.updates()
    }

    func current() async throws -> WorkoutState? {
        try await enter(.current)
        return try await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await enter(.start)
        try await base.start(initial)
        try refuse(.start, afterwards: true)
    }

    @discardableResult
    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await enter(.apply)
        return try await base.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await enter(.finish)
        return try await base.finish(endedAt: endedAt)
    }

    func discard(endedAt: Date) async throws {
        try await enter(.discard)
        try await base.discard(endedAt: endedAt)
        try refuse(.discard, afterwards: true)
    }
}

/// A session whose stream the test writes by hand: for what no well-behaved client does on one phone (a
/// stream that ends, an update for another workout with no end between). `current()` answers the last
/// state the test published.
actor ScriptedSession: WorkoutSessionClient {
    private var state: WorkoutState?
    private var streams: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []
    private(set) var discards = 0

    init(live: WorkoutState?) {
        state = live
    }

    var subscribers: Int {
        streams.count
    }

    func publish(_ next: WorkoutState?) {
        state = next?.phase == .live ? next : nil
        for stream in streams {
            stream.yield(WorkoutSessionUpdate(state: next))
        }
    }

    func endStreams() {
        for stream in streams {
            stream.finish()
        }
        streams = []
    }

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(WorkoutSessionUpdate(state: state))
        streams.append(continuation)
        return stream
    }

    func current() -> WorkoutState? {
        state
    }

    func start(_ initial: WorkoutState) throws {
        throw WorkoutSessionError.workoutInProgress(initial.id)
    }

    @discardableResult
    func apply(_: WorkoutEvent) throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func finish(endedAt _: Date) throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func discard(endedAt _: Date) throws {
        discards += 1
        throw WorkoutSessionError.noLiveWorkout
    }
}
