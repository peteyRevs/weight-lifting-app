import Foundation
import LedgerDomain
@testable import LedgerHealth
import Synchronization

/// A scripted `HKWorkoutSession` + `HKLiveWorkoutBuilder` (F16 S2a): it records every call, and every callback the
/// test plays, in one ordered log, and answers as the script says. With `autoplay`, `prepare()` plays `.prepared`
/// as HealthKit would; without, the test plays it.
final class ScriptedSession: WorkoutSessionDriver {
    /// How one `startMirroring()` ends.
    enum Mirroring: Sendable {
        case connects, fails
        /// Never answers: returns only when its task is cancelled, as the driver promises.
        case hangs
    }

    let callbacks: AsyncStream<WorkoutSessionCallback>
    /// The log's entries as they are recorded, for a test to wait on.
    let calls: AsyncStream<String>
    private let autoplay: Bool
    private let sink: AsyncStream<WorkoutSessionCallback>.Continuation
    private let callsSink: AsyncStream<String>.Continuation
    private let state: Mutex<State>

    private struct State {
        var log: [String] = []
        var mirroring: [Mirroring]
    }

    /// `mirroring` answers the `startMirroring()` calls in turn; past its end, each connects.
    init(autoplay: Bool = true, mirroring: [Mirroring] = []) {
        self.autoplay = autoplay
        state = Mutex(State(mirroring: mirroring))
        (callbacks, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (calls, callsSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Every call and played callback (`→prepared`), in order.
    var log: [String] {
        state.withLock { $0.log }
    }

    /// Plays a delegate callback, logged as `→` and its name.
    func play(_ callback: WorkoutSessionCallback) {
        record("→" + Self.name(of: callback))
        sink.yield(callback)
    }

    /// Returns once `call` has been recorded since the last wait.
    func wait(for call: String) async {
        for await recorded in calls where recorded == call {
            return
        }
    }

    func prepare() {
        record("prepare")
        if autoplay {
            play(.state(.prepared, Date(timeIntervalSince1970: 0)))
        }
    }

    func startMirroring() async throws {
        record("startMirroring")
        let answer = state.withLock { $0.mirroring.isEmpty ? .connects : $0.mirroring.removeFirst() }
        switch answer {
        case .connects:
            return
        case .fails:
            throw HealthError.underlying(code: 100)
        case .hangs:
            let (never, keep) = AsyncStream<Void>.makeStream()
            for await _ in never {}
            withExtendedLifetime(keep) {}
            throw CancellationError()
        }
    }

    func startActivity(at _: Date) {
        record("startActivity")
    }

    func beginCollection(at _: Date) {
        record("beginCollection")
    }

    func end() {
        record("end")
    }

    func discardWorkout() {
        record("discardWorkout")
    }

    private func record(_ entry: String) {
        state.withLock { $0.log.append(entry) }
        callsSink.yield(entry)
    }

    private static func name(of callback: WorkoutSessionCallback) -> String {
        switch callback {
        case let .state(state, _): "\(state)"
        case let .failed(error): "failed \(error)"
        case .heartRate: "heartRate"
        case .mirrorDisconnected: "mirrorDisconnected"
        }
    }
}

/// Hands out the test's session.
struct ScriptedProvider: WorkoutSessionProvider {
    var status = HealthAuthorization.authorized
    var session = ScriptedSession()

    func authorization() -> HealthAuthorization {
        status
    }

    func requestAuthorization() -> HealthAuthorization {
        status
    }

    func makeSession() -> any WorkoutSessionDriver {
        session
    }
}

/// A clock whose time moves only when the test moves it (testing-strategy §3). Each sleep is registered under the
/// lock in the step that suspends its task, and announced on `sleeps` in that same step, so a test that has read
/// a sleep from `sleeps` knows that `advance(by:)` wakes it. Never swift-clocks' `TestClock`, whose
/// background-priority yields stalled a busy runner (#122; `RestCoverClock`).
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let wake: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var begun = 0
        var sleepers: [Int: Sleeper] = [:]
        /// Sleeps cancelled before they were registered.
        var cancelled: Set<Int> = []
    }

    /// Each registered sleep's length, in the order they were registered.
    let sleeps: AsyncStream<Duration>
    private let sleepsSink: AsyncStream<Duration>.Continuation
    private let state = Mutex(State())

    init() {
        (sleeps, sleepsSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
        let id = state.withLock { state in
            state.begun += 1
            return state.begun
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, any Error>) in
                let answer = state.withLock { state -> Result<Void, any Error>? in
                    if state.cancelled.remove(id) != nil {
                        return .failure(CancellationError())
                    }
                    guard deadline > state.now else {
                        return .success(())
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, wake: wake)
                    sleepsSink.yield(state.now.duration(to: deadline))
                    return nil
                }
                if let answer {
                    wake.resume(with: answer)
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.wake.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `duration` and wakes every sleep that ends by then.
    func advance(by duration: Duration) {
        let woken = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys {
                state.sleepers[id] = nil
            }
            return due.values.map(\.wake)
        }
        for wake in woken {
            wake.resume()
        }
    }

    /// The next registered sleep that is not `skipped`'s length.
    func nextSleep(skipping skipped: Duration) async -> Duration? {
        for await sleep in sleeps where sleep != skipped {
            return sleep
        }
        return nil
    }
}
