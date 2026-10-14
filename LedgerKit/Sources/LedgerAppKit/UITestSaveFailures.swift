import Foundation
import LedgerDomain

/// A UI test's failing save (F10 S7a, fix round 1): `-LEDGER_UITEST_FAIL_FINISH <count>` beside
/// `-LEDGER_UITEST` makes the session's `finish` refuse its first `count` calls, before they reach the host,
/// and then save as it always does. It exists because a save that fails cannot be produced in the app
/// otherwise (it needs a full disk), and the alert of a failed save, and "Try again", must be seen there.
///
/// Read as `UITestClock` reads its argument, and like it **in Debug builds only**: a Release build reads no
/// argument here and binds the host itself.
nonisolated enum UITestSaveFailures {
    static let argument = "-LEDGER_UITEST_FAIL_FINISH"

    /// The argument is there and its value is missing or is no count from 1 up.
    struct InvalidCount: Error, Equatable {
        let value: String?
    }

    /// How many calls of `finish` fail; nil when the arguments ask for none, or are not a UI test's.
    static func count(arguments: [String]) throws -> Int? {
        guard arguments.contains("-LEDGER_UITEST"), let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        guard let value, let count = Int(value), count > 0 else {
            throw InvalidCount(value: value)
        }
        return count
    }

    /// `count(arguments:)` for this launch. A value that cannot be read stops the launch, as a wrong date does.
    static func liveCount(arguments: [String]) -> Int? {
        #if DEBUG
            do {
                return try count(arguments: arguments)
            } catch {
                fatalError("\(argument) needs a count from 1 up: \(error)")
            }
        #else
            return nil
        #endif
    }
}

#if DEBUG
    /// The host behind a `finish` that refuses its first `failures` calls; every other call is the host's.
    actor UITestFailingFinishSession: WorkoutSessionClient {
        /// What a refused `finish` throws: nothing reached the host, and the workout stays live.
        struct Refused: Error {}

        private let base: any WorkoutSessionClient
        private var failures: Int

        init(base: any WorkoutSessionClient, failures: Int) {
            self.base = base
            self.failures = failures
        }

        func updates() async -> AsyncStream<WorkoutSessionUpdate> {
            await base.updates()
        }

        func current() async throws -> WorkoutState? {
            try await base.current()
        }

        func start(_ initial: WorkoutState) async throws {
            try await base.start(initial)
        }

        func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
            try await base.apply(event)
        }

        func finish(endedAt: Date) async throws -> WorkoutState {
            guard failures == 0 else {
                failures -= 1
                throw Refused()
            }
            return try await base.finish(endedAt: endedAt)
        }

        func discard(endedAt: Date) async throws {
            try await base.discard(endedAt: endedAt)
        }
    }
#endif
