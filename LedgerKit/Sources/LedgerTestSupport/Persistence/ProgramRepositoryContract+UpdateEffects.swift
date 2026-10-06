import Foundation
import LedgerDomain

/// `ProgramRepository.update` (F11 S3), continued: which program is active (criterion 6), what an observer
/// hears (criteria 3 and 5) and what a cancelled call stores (criterion 8).
extension ProgramRepositoryContract {
    /// Criterion 6, as far as the protocol shows it: a builder edit never changes which program is active. A
    /// result's `isActive` is part of the program `save` stores, so a change that sets it is saved as `save`
    /// saves it (S3 notes, "Decisions and deviations").
    static func updateKeepsActivity(_ repository: any ProgramRepository) async throws -> String? {
        let first = try program(number: 1, isActive: true)
        let second = try program(number: 2, isActive: false)
        try await repository.save(first)
        try await repository.save(second)
        let inactive = try await repository.update(second.id, renamed)
        let afterInactive = try await repository.active()
        let active = try await repository.update(first.id, renamed)
        let afterActive = try await repository.active()
        let promoted = try await repository.update(second.id) { stored in
            var changed = stored
            changed.isActive = true
            return changed
        }
        let afterPromotion = try await repository.active()
        let retired = try await repository.update(second.id) { stored in
            var changed = stored
            changed.isActive = false
            return changed
        }
        var secondActive = renamed(second)
        secondActive.isActive = true
        return try await ContractCheck.first(
            same(inactive, renamed(second), "what the update of the inactive program returned"),
            same(afterInactive, first, "active() after it"),
            same(active, renamed(first), "what the update of the active program returned"),
            same(afterActive, renamed(first), "active() after it"),
            same(promoted, secondActive, "what a change that sets isActive returned"),
            same(afterPromotion, secondActive, "active() after it"),
            same(retired, renamed(second), "what a change that clears isActive returned"),
            same(repository.active(), nil, "active() after it")
        )
    }

    /// A stream keeps its newest value only, so a value emitted for an update that changed nothing would be
    /// replaced by the next real one before this read it. What this shows is that no such update is ever
    /// seen as a change; `ProgramUpdateTests` counts the database's emissions one by one.
    static func updateObserved(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        var values = repository.observeActive().makeAsyncIterator()
        let first = await values.next()
        _ = try await repository.update(program.id) { $0 }
        _ = try await repository.update(program.id) { stored in
            var reordered = stored
            reordered.weeks.reverse()
            return reordered
        }
        _ = await refusal { _ = try await repository.update(program.id) { _ in throw ChangeFailure(code: 1) } }
        _ = await refusal {
            _ = try await repository.update(program.id) { stored in
                var result = stored
                result.days[0].slots[0].sets = 99
                return result
            }
        }
        _ = try await repository.update(program.id, renamed)
        let second = await values.next()
        let edited = try await repository.update(program.id) { try Self.edited($0) }
        let third = await values.next()
        return ContractCheck.first(
            same(first ?? nil, program, "the first value"),
            same(second ?? nil, renamed(program), "the value after the first update that changes the program"),
            same(third ?? nil, edited, "the value after the next")
        )
    }

    static func updateCancelledBefore(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let calls = Tally()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.update(program.id) { stored in
                calls.add()
                return renamed(stored)
            }
        }
        let outcome = switch await cancelled.result {
        case .success: "returned"
        case .failure(is CancellationError): "CancellationError"
        case let .failure(error): String(String(reflecting: error).prefix(200))
        }
        return try await ContractCheck.first(
            ContractCheck.expect(outcome, "CancellationError", "the cancelled call"),
            ContractCheck.expect(calls.count, 0, "the calls of the change"),
            same(repository.active(), program, "active() after the cancelled call")
        )
    }

    /// The task is cancelled while the store's write runs, after its read: every store rolls back and throws
    /// (criterion 12), so a store tested over the in-memory stores meets the path it meets on a phone.
    static func updateCancelledInside(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let cancellation = TaskCancelSwitch()
        let result = await cancellation.run {
            try await repository.update(program.id) { stored in
                cancellation.fire()
                return try edited(stored)
            }
        }.result
        let outcome = switch result {
        case .success: "returned"
        case .failure(is CancellationError): "CancellationError"
        case let .failure(error): String(String(reflecting: error).prefix(200))
        }
        return try await ContractCheck.first(
            ContractCheck.expect(outcome, "CancellationError", "the call cancelled inside its change"),
            same(repository.active(), program, "active() after it")
        )
    }
}
