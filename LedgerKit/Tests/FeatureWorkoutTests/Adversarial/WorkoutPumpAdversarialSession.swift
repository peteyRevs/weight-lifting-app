import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The real engine behind a session the test drives by hand (G2, F10 S5): every `apply` of the store can be
/// made to wait before it reaches the engine, a numbered one can be refused, the stream can be kept behind
/// the calls' answers and let on one update at a time, and another hand (the watch, later) can change the
/// workout in between. It keeps the client's rules as `FakeWorkoutSessionClient` does: an event the engine
/// accepts is published once, an ignored one returns the workout as it stands and publishes nothing.
///
/// Unlike a host it does not take its calls one at a time while one waits: `elsewhere` runs while an `apply`
/// is parked, as a peer's event reaches the engine whenever it arrives.
actor PumpSession: WorkoutSessionClient {
    nonisolated struct Refused: Error, Equatable {}

    private struct Subscriber {
        let continuation: AsyncStream<WorkoutSessionUpdate>.Continuation
        var behind: [WorkoutSessionUpdate] = []
    }

    /// The events the store asked for that reached the engine, in order.
    private(set) var applied: [WorkoutEvent] = []
    /// How many streams were opened.
    private(set) var streamsOpened = 0
    /// How many `apply` calls are waiting to be released: read from the main actor without a hop.
    nonisolated let waiting = LockIsolated(0)

    private var live: WorkoutState?
    private var seq: UInt64 = 1
    private var subscribers: [Subscriber] = []
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var calls = 0
    private var refused: Set<Int> = []
    private var holdsEveryApply = false
    private var holdsEveryAnswer = false
    private var isBehind = false
    private var throwsWhenCancelled = false
    private var refusesDiscard = false

    init(live: WorkoutState) {
        self.live = WorkoutEngine.reduce(nil, Self.envelope(.started(live), in: live.id, seq: 1)).0
    }

    // MARK: What the test sets

    /// Every `apply` from now on waits, before it reaches the engine, for one `release()`.
    func holdEveryApply(_ holds: Bool = true) {
        holdsEveryApply = holds
    }

    /// Every `apply` from now on waits, after the engine took its event and the update went out, for one
    /// `release()`: an answer that comes back after the stream has shown it.
    func holdEveryAnswer(_ holds: Bool = true) {
        holdsEveryAnswer = holds
    }

    /// Lets the oldest waiting `apply` on.
    func release() {
        guard !parked.isEmpty else {
            return
        }
        waiting.withValue { $0 -= 1 }
        parked.removeFirst().resume()
    }

    /// The `apply` calls with these numbers, counted from 1 over the session's life, throw `Refused` and
    /// change nothing.
    func refuse(calls numbers: Set<Int>) {
        refused = numbers
    }

    /// While behind, updates are kept from every open stream until `deliver`.
    func keepStreamsBehind(_ behind: Bool = true) {
        isBehind = behind
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

    /// An `apply` whose task was cancelled while it waited throws `CancellationError` and changes nothing.
    func throwWhenCancelled() {
        throwsWhenCancelled = true
    }

    func refuseDiscard(_ refuses: Bool = true) {
        refusesDiscard = refuses
    }

    /// A change by another hand: it reaches the engine at once and is not listed in `applied`.
    @discardableResult
    func elsewhere(_ event: WorkoutEvent) throws -> WorkoutState {
        try reduce(event)
    }

    // MARK: WorkoutSessionClient

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream(bufferingPolicy: .unbounded)
        streamsOpened += 1
        continuation.yield(WorkoutSessionUpdate(state: live))
        subscribers.append(Subscriber(continuation: continuation))
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
        if throwsWhenCancelled {
            try Task.checkCancellation()
        }
        if refused.contains(number) {
            throw Refused()
        }
        applied.append(event)
        let answer = try reduce(event)
        if holdsEveryAnswer {
            waiting.withValue { $0 += 1 }
            await withCheckedContinuation { parked.append($0) }
        }
        return answer
    }

    func finish(endedAt: Date) throws -> WorkoutState {
        try reduce(.finished(endedAt: endedAt))
    }

    func discard(endedAt: Date) throws {
        if refusesDiscard {
            throw Refused()
        }
        _ = try reduce(.discarded(endedAt: endedAt))
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

/// A store on a `PumpSession`, following it, as one presentation of the cover (G2, F10 S5).
@MainActor
struct PumpBench {
    let session: PumpSession
    let store: WorkoutStore
    let following: Task<Void, Never>
    let running: WorkoutState
    /// The store's injected date: `Fixtures.now` until the test moves it.
    let clock: LockIsolated<Date>

    /// The spec's five straight exercises (`EventBuilders.seedSession`), the first and the third with a last
    /// workout, so "Repeat" does something.
    ///
    /// With `ticking`, every reading of the store's date moves the clock on by a seeded step of 0 to 0.4 s.
    /// The store reads it once for each tap it plans, so the same taps meet the same moments however they
    /// arrive, and some un-logs fall inside the one-second guard of criterion 18 and some after it.
    static func make(
        ticking seed: UInt64? = nil,
        by steps: ClosedRange<Double> = 0 ... 0.4,
        _ change: (inout WorkoutState) -> Void = { _ in }
    ) async throws -> PumpBench {
        var workout = EventBuilders.seedSession()
        for index in [0, 2] {
            workout.exercises[index].lastPerformance = LastPerformance(
                date: Fixtures.now.addingTimeInterval(-7 * 86400), sets: 4, reps: 6, load: .pounds(150)
            )
        }
        change(&workout)
        let client = PumpSession(live: workout)
        let time = LockIsolated(Fixtures.now)
        let generator = LockIsolated(SplitMix64(seed: seed ?? 0))
        let cover = withTestDependencies {
            $0.workoutSession = client
            $0.date = DateGenerator {
                guard seed != nil else {
                    return time.value
                }
                let step = generator.withValue { Double.random(in: steps, using: &$0) }
                return time.withValue {
                    $0 += step
                    return $0
                }
            }
        } operation: {
            WorkoutStore()
        }
        let task = Task { await cover.follow() }
        await eventually("the session's first update") { cover.shown != nil }
        return PumpBench(session: client, store: cover, following: task, running: workout, clock: time)
    }

    func set(_ exercise: Int, _ row: Int) -> SetID {
        running.exercises[exercise].sets[row].id
    }

    func tap(_ edits: WorkoutEdit...) {
        for edit in edits {
            store.send(.edit(edit))
        }
    }

    /// The session's workout, and the page once it shows it.
    @discardableResult
    func settled() async -> WorkoutState? {
        await session.deliver()
        let truth = await session.current()
        await eventually("the page to show the session's workout") { store.shown == truth }
        return truth
    }

    /// Runs a drain to its end, letting each waiting call on; `between` runs while each one waits.
    func drainReleasing(_ between: @MainActor () async -> Void = {}) async {
        let finished = LockIsolated(false)
        let draining = Task {
            await store.drain()
            finished.setValue(true)
        }
        let waiting = session.waiting
        while await eventually("a call or the drain's end", { finished.value || waiting.value > 0 }), !finished.value {
            await between()
            await session.release()
        }
        await draining.value
    }

    /// The weight of a row in the session's workout, in pounds as text.
    func weight(_ exercise: Int, _ row: Int) async -> String {
        await session.current()?.exercises[exercise].sets[row].weight.formatted(in: .lb) ?? "no workout"
    }
}
