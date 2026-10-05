import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Observation
import Synchronization
import Testing

/// Suspends until `condition` holds of what an observable object shows. No polling and no sleep: `Observations`
/// wakes on each change of what `condition` read. A test that waits for something that never comes ends at its
/// suite's time limit, which cancels the wait.
func until(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations(condition) where holds {
        return
    }
}

extension RootGate {
    /// Runs `body` while a new gate follows `programs`, as the root's task does, and cancels the follow when
    /// `body` ends. With `launch`, the launch's pass waits there before it returns the store.
    static func following(
        _ programs: any ProgramRepository,
        after launch: Latch? = nil,
        _ body: (RootGate) async throws -> Void
    ) async rethrows {
        let gate = RootGate()
        let follow = Task {
            await gate.follow {
                await launch?.pass()
                return programs
            }
        }
        defer { follow.cancel() }
        try await body(gate)
    }

    /// Suspends until the gate has an answer, and returns it.
    func answer() async -> Destination {
        await until { self.destination != .loading }
        return destination
    }

    /// Suspends until the gate shows something else than `current`, and returns it.
    func change(from current: Destination) async -> Destination {
        await until { self.destination != current }
        return destination
    }
}

extension Harness {
    /// A gate that has followed `composition` to its first answer by the call the root's own task makes
    /// (`RootGate.follow(_:in:)`: the launch's pass, then the active program). A root handed this gate shows
    /// its screen in the first tree a test reads; a root that makes its own gate shows the ground colour
    /// until an awaited read has returned, which a test that reads at once never sees the end of.
    func gate(following composition: AppComposition) async -> RootGate {
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        _ = await gate.answer()
        follow.cancel()
        await follow.value
        return gate
    }

    /// A lifter who has a program: a composition booted on a database that holds the default program, saved
    /// and active as onboarding saves it, its launch's pass run, and a gate that has followed it to the tabs.
    func bootedWithAProgram() async throws -> (composition: AppComposition, gate: RootGate) {
        let composition = booted()
        await composition.resume(in: .active)
        try await #require(composition.stores).programs.save(Fixtures.defaultProgram())
        return await (composition, gate(following: composition))
    }
}

/// A program store a test scripts: it answers each observation with the active program it was given, then
/// with each one the test sets, and counts the observations it was asked for. `fail()` ends every stream, as
/// the database's does when the active program cannot be read, and each later one at once, until `recover`.
final nonisolated class ScriptedPrograms: ProgramRepository {
    private struct State {
        var active: Program?
        var isFailing = false
        var observations = 0
        var streams: [AsyncStream<Program?>.Continuation] = []
    }

    private let state: Mutex<State>

    init(active: Program? = nil) {
        state = Mutex(State(active: active))
    }

    /// How many times `observeActive()` was called: each call is one read of the active program.
    var observations: Int {
        state.withLock(\.observations)
    }

    func set(_ program: Program?) {
        let streams = state.withLock { state in
            state.active = program
            return state.streams
        }
        for stream in streams {
            stream.yield(program)
        }
    }

    func fail() {
        let streams = state.withLock { state in
            state.isFailing = true
            defer { state.streams = [] }
            return state.streams
        }
        for stream in streams {
            stream.finish()
        }
    }

    func recover(active program: Program?) {
        state.withLock { state in
            state.isFailing = false
            state.active = program
        }
    }

    func observeActive() -> AsyncStream<Program?> {
        let (stream, continuation) = AsyncStream<Program?>.makeStream()
        state.withLock { state in
            state.observations += 1
            if state.isFailing {
                continuation.finish()
            } else {
                continuation.yield(state.active)
                state.streams.append(continuation)
            }
        }
        return stream
    }

    func active() async throws -> Program? {
        state.withLock(\.active)
    }

    func save(_ program: Program) async throws {
        set(program)
    }

    func setActive(_: ProgramID) async throws {}

    func delete(_: ProgramID) async throws {
        set(nil)
    }
}

/// Where a test holds a call open: the call awaits `pass()`, the test awaits `entered()`, looks at what holds
/// meanwhile, then calls `open()`. Once open it stays open. A task cancelled while it waits passes at once.
final nonisolated class Latch: Sendable {
    private let arrivals = AsyncStream<Void>.makeStream()
    private let openings = AsyncStream<Void>.makeStream()
    private let isOpen = Mutex(false)

    func pass() async {
        arrivals.continuation.yield()
        guard !isOpen.withLock(\.self) else {
            return
        }
        for await _ in openings.stream {
            return
        }
    }

    /// Returns once a caller has reached `pass()`.
    func entered() async {
        for await _ in arrivals.stream {
            return
        }
    }

    func open() {
        isOpen.withLock { $0 = true }
        openings.continuation.yield()
    }
}
