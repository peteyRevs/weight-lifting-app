import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 criterion 5: the protocol is six calls. `resumeFromStore()` is not one of them: recovery is the
/// host's launch step (S2), and each of the six waits for it. The protocol's behaviour is
/// `WorkoutSessionClientContract`'s, run on every implementation in `LedgerSyncTests`.
@Suite("WorkoutSessionClient", .tags(.domain), .timeLimit(.minutes(1)))
struct WorkoutSessionClientTests {
    /// Conforms with the six calls and nothing else, so it stops compiling when the protocol asks for more.
    struct SixCalls: WorkoutSessionClient {
        func updates() async -> AsyncStream<WorkoutSessionUpdate> {
            AsyncStream { $0.finish() }
        }

        func current() async throws -> WorkoutState? {
            nil
        }

        func start(_ initial: WorkoutState) async throws {
            throw WorkoutSessionError.notStartable(initial.id)
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

    @Test("A type with the six calls is a session client, and apply's result may go unused")
    func protocol_isTheSixCalls() async throws {
        let client: any WorkoutSessionClient = SixCalls()
        let session = EventBuilders.seedSession()
        var updates = await client.updates().makeAsyncIterator()
        #expect(await updates.next() == nil)
        #expect(try await client.current() == nil)
        await #expect(throws: WorkoutSessionError.notStartable(session.id)) { try await client.start(session) }
        // No `_ =`: the protocol marks the result discardable, for a caller that only watches the stream.
        await #expect(throws: WorkoutSessionError.noLiveWorkout) { try await client.apply(.restSkipped) }
        let later = session.startedAt
        await #expect(throws: WorkoutSessionError.noLiveWorkout) { _ = try await client.finish(endedAt: later) }
        await #expect(throws: WorkoutSessionError.noLiveWorkout) { try await client.discard(endedAt: later) }
    }

    @Test("The errors compare by case and by the workout they name")
    func errors_compareByCaseAndWorkout() {
        let one = EventBuilders.workoutID
        let other = WorkoutID(EventBuilders.uuid(0xF101))
        #expect(WorkoutSessionError.workoutInProgress(one) == .workoutInProgress(one))
        #expect(WorkoutSessionError.workoutInProgress(one) != .workoutInProgress(other))
        #expect(WorkoutSessionError.workoutInProgress(one) != .notStartable(one))
        #expect(WorkoutSessionError.incompleteLog(one) != .notStartable(one))
        #expect(WorkoutSessionError.incompleteLog(one) == .incompleteLog(one))
        #expect(WorkoutSessionError.noLiveWorkout == .noLiveWorkout)
        #expect(WorkoutSessionError.noLiveWorkout != .incompleteLog(one))
        // The refusal of an end the engine ignored names no workout and no date: the caller knows both.
        #expect(WorkoutSessionError.invalidEndDate == .invalidEndDate)
        #expect(WorkoutSessionError.invalidEndDate != .noLiveWorkout)
    }
}
