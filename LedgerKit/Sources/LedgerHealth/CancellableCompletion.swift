import Foundation
import LedgerDomain
import Synchronization

/// Awaits a HealthKit call that answers through a completion handler (`(Bool, Error?) -> Void`), and returns as soon
/// as its task is cancelled, whatever HealthKit does: `startMirroringToCompanionDevice()` can hang (R1 §2.5 gotcha
/// 5), and the store's timeouts race these calls in task groups, which wait for every child (F16 S2a decision 3,
/// S3). A failure is a `HealthError`; a `false` with no error, `underlying(code: 0)`.
func cancellableCompletion(_ call: (@escaping @Sendable (Bool, (any Error)?) -> Void) -> Void) async throws {
    let once = ResumeOnce()
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            once.arm(continuation)
            call { success, error in
                let failure = error.map { HealthError($0) } ?? .underlying(code: 0)
                once.resume(with: success ? .success(()) : .failure(failure))
            }
        }
    } onCancel: {
        once.resume(with: .failure(CancellationError()))
    }
}

/// Resumes a continuation once: with HealthKit's answer or with the task's cancellation, whichever comes first.
/// HealthKit answers on its own queue, synchronously, so the slot sits behind a `Mutex`
/// (engineering-standards §4's exception for state a framework callback writes).
private final class ResumeOnce: Sendable {
    private struct Slot {
        var continuation: CheckedContinuation<Void, any Error>?
        var early: Result<Void, any Error>?
        var isDone = false
    }

    private let slot = Mutex(Slot())

    /// Waits with `continuation`, or resumes it at once with an answer that came before it.
    func arm(_ continuation: CheckedContinuation<Void, any Error>) {
        let early = slot.withLock { slot -> Result<Void, any Error>? in
            guard let early = slot.early else {
                slot.continuation = continuation
                return nil
            }
            slot.isDone = true
            return early
        }
        if let early {
            continuation.resume(with: early)
        }
    }

    func resume(with result: Result<Void, any Error>) {
        let continuation = slot.withLock { slot -> CheckedContinuation<Void, any Error>? in
            guard !slot.isDone else {
                return nil
            }
            guard let continuation = slot.continuation.take() else {
                slot.early = slot.early ?? result
                return nil
            }
            slot.isDone = true
            return continuation
        }
        continuation?.resume(with: result)
    }
}
