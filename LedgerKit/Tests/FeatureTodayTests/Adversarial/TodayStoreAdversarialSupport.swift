import Dependencies
@testable import FeatureToday
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Synchronization

// F09 S5 adversarial round 1 (G2): what the store's attacks share. Sources a test drives by hand, a wait that
// ends, and a count of what the store publishes.

/// One source the test drives: every stream it hands out receives what the test yields, and it counts the
/// streams it handed out and those still listened to, so a duplicated or a leaked observation shows.
final nonisolated class Feed<Value: Sendable>: Sendable {
    private struct State {
        var continuations: [Int: AsyncStream<Value>.Continuation] = [:]
        var opened = 0
        /// Yielded to each new stream at once, as a store's observation yields what it holds.
        var first: Value?
    }

    private let state = Mutex(State())

    init(first: Value? = nil) {
        state.withLock { $0.first = first }
    }

    /// The streams handed out so far.
    var opened: Int {
        state.withLock { $0.opened }
    }

    /// The streams still listened to.
    var listening: Int {
        state.withLock { $0.continuations.count }
    }

    func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .unbounded)
        let (number, first) = state.withLock { state -> (Int, Value?) in
            state.opened += 1
            state.continuations[state.opened] = continuation
            return (state.opened, state.first)
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.continuations[number] = nil }
        }
        if let first {
            continuation.yield(first)
        }
        return stream
    }

    /// Sends `value` to every stream, and to each later one as its first.
    func yield(_ value: Value) {
        let all = state.withLock { state -> [AsyncStream<Value>.Continuation] in
            state.first = value
            return Array(state.continuations.values)
        }
        for continuation in all {
            continuation.yield(value)
        }
    }

    /// Ends every stream, as a store ends an observation whose read failed. Later streams are whole again.
    func finish() {
        let all = state.withLock { Array($0.continuations.values) }
        for continuation in all {
            continuation.finish()
        }
    }
}

nonisolated struct NotScripted: Error {}

nonisolated struct ScriptedPrograms: ProgramRepository {
    let feed: Feed<Program?>

    func observeActive() -> AsyncStream<Program?> {
        feed.stream()
    }

    func active() async throws -> Program? {
        throw NotScripted()
    }

    func save(_: Program) async throws {
        throw NotScripted()
    }

    func update(_: ProgramID, _: @Sendable (Program) throws -> Program) async throws -> Program {
        throw NotScripted()
    }

    func setActive(_: ProgramID) async throws {
        throw NotScripted()
    }

    func delete(_: ProgramID) async throws {
        throw NotScripted()
    }
}

nonisolated struct ScriptedSettings: SettingsRepository {
    let feed: Feed<Settings>

    func observe() -> AsyncStream<Settings> {
        feed.stream()
    }

    func load() async throws -> Settings {
        throw NotScripted()
    }

    func save(_: Settings) async throws {
        throw NotScripted()
    }

    func seedIfAbsent(_: Settings) async throws {
        throw NotScripted()
    }
}

nonisolated struct ScriptedExercises: ExerciseRepository {
    let feed: Feed<[Exercise]>

    func observeAll() -> AsyncStream<[Exercise]> {
        feed.stream()
    }

    func all() async throws -> [Exercise] {
        throw NotScripted()
    }

    func exercise(id _: ExerciseID) async throws -> Exercise? {
        throw NotScripted()
    }

    func search(_: String, equipment _: Equipment?, muscle _: MuscleGroup?) async throws -> [Exercise] {
        throw NotScripted()
    }

    func save(_: Exercise) async throws {
        throw NotScripted()
    }

    func seedIfNeeded(_: [Exercise], version _: Int) async throws {
        throw NotScripted()
    }
}

/// The workout store by hand: the recent workouts are a feed, and each read of a stretch of time answers
/// with `week` as it stood when the read began, as a database's read does. While `isHolding`, a read waits until the
/// test lets it go,
/// and each waits by itself, so a test can end them in any order.
final nonisolated class ScriptedWorkouts: WorkoutRepository {
    private struct State {
        var week: [WorkoutState] = []
        var isHolding = false
        var isFailing = false
        var reads = 0
        var held: [Int: AsyncStream<Void>.Continuation] = [:]
    }

    let feed: Feed<[WorkoutState]>
    private let state = Mutex(State())

    init(feed: Feed<[WorkoutState]>) {
        self.feed = feed
    }

    /// The reads of a stretch of time begun so far.
    var reads: Int {
        state.withLock { $0.reads }
    }

    /// The numbers of the reads that wait, in order; a read's number is its place among all reads, from 1.
    var waiting: [Int] {
        state.withLock { $0.held.keys.sorted() }
    }

    var week: [WorkoutState] {
        get { state.withLock { $0.week } }
        set { state.withLock { $0.week = newValue } }
    }

    var isHolding: Bool {
        get { state.withLock { $0.isHolding } }
        set { state.withLock { $0.isHolding = newValue } }
    }

    var isFailing: Bool {
        get { state.withLock { $0.isFailing } }
        set { state.withLock { $0.isFailing = newValue } }
    }

    /// Lets read `number` go.
    func release(_ number: Int) {
        state.withLock { $0.held.removeValue(forKey: number) }?.finish()
    }

    func workouts(in _: Range<Date>) async throws -> [WorkoutState] {
        let (gate, seen) = state.withLock { state -> (AsyncStream<Void>?, [WorkoutState]) in
            state.reads += 1
            guard state.isHolding else {
                return (nil, state.week)
            }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            state.held[state.reads] = continuation
            return (stream, state.week)
        }
        if let gate {
            // A stream, not a continuation: it ends when the reading task is cancelled and nobody lets it go.
            for await _ in gate {}
        }
        if isFailing {
            throw NotScripted()
        }
        return seen
    }

    func observeRecent(limit _: Int) -> AsyncStream<[WorkoutState]> {
        feed.stream()
    }

    func historyEntries() async throws -> [HistoryEntry] {
        throw NotScripted()
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        AsyncStream { $0.finish() }
    }

    func observeWorkout(id _: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        AsyncStream { $0.finish() }
    }

    func materialize(_: WorkoutState, slotUpdates _: [Slot], droppingLog _: Bool) async throws -> Bool {
        throw NotScripted()
    }

    func workout(id _: WorkoutID) async throws -> WorkoutState? {
        throw NotScripted()
    }

    func recent(limit _: Int) async throws -> [WorkoutState] {
        throw NotScripted()
    }

    func updateSets(workoutExerciseID _: WorkoutExerciseID, sets _: [LoggedSet]) async throws {
        throw NotScripted()
    }

    func delete(id _: WorkoutID) async throws {
        throw NotScripted()
    }
}

nonisolated struct ScriptedSession: WorkoutSessionClient {
    let feed: Feed<WorkoutSessionUpdate>

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        feed.stream()
    }

    func current() async throws -> WorkoutState? {
        throw WorkoutSessionError.noLiveWorkout
    }

    func start(_: WorkoutState) async throws {
        throw WorkoutSessionError.noLiveWorkout
    }

    func apply(_: WorkoutEvent) async throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func finish(endedAt _: Date) async throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func discard(endedAt _: Date) async throws {
        throw WorkoutSessionError.noLiveWorkout
    }
}
