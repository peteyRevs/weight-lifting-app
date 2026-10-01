/// One clause of a repository protocol's documented contract (`ExerciseRepositoryContract`,
/// `ProgramRepositoryContract`). Every implementation runs the same clauses: the GRDB repositories in
/// `LedgerPersistenceTests` (F05), and F07's in-memory fakes, so a fake cannot drift from the real semantics
/// (testing-strategy §2.2). `check` gets a fresh, empty repository and returns `nil` when it keeps the clause,
/// or what it did instead. Public API only: no `@testable`, no `import Testing`.
public struct ContractClause<Repository>: Sendable, CustomStringConvertible {
    public let name: String
    public let check: @Sendable (Repository) async throws -> String?

    public init(_ name: String, _ check: @escaping @Sendable (Repository) async throws -> String?) {
        self.name = name
        self.check = check
    }

    public var description: String {
        name
    }
}

/// What a clause returns: `nil` when the repository kept it, else a line saying what it did instead.
enum ContractCheck {
    /// `nil` when `actual == expected`, else a line naming both.
    static func expect<Value: Equatable>(_ actual: Value, _ expected: Value, _ what: String) -> String? {
        actual == expected ? nil : "\(what): got \(actual), expected \(expected)"
    }

    /// The first issue among `checks`, in the order given, or `nil` when every one passed. Unlike a `??`
    /// chain, every operand may `await`.
    static func first(_ checks: String?...) -> String? {
        checks.lazy.compactMap(\.self).first
    }

    /// `nil` when `body` throws an error equal to `expected`, else what happened.
    static func expectError<Failure: Error & Equatable>(
        _ expected: Failure,
        _ body: () async throws -> Void
    ) async -> String? {
        do {
            try await body()
            return "did not throw \(expected)"
        } catch let error as Failure where error == expected {
            return nil
        } catch {
            return "threw \(error), expected \(expected)"
        }
    }
}
