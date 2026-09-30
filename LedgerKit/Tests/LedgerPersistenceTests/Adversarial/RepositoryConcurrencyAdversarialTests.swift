import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: the repositories are `Sendable` structs and the `DatabaseQueue` is the actor
/// boundary (brief, Non-functional), so racing saves and reads only ever see whole programs.
@Suite("Adversarial S2 · repository concurrency", .tags(.persistence), .timeLimit(.minutes(1)))
struct RepositoryConcurrencyAdversarialTests {
    static func requireSendable(_: some Sendable) {}

    @Test("Both repositories are Sendable and cross task boundaries")
    func repositories_areSendable() async throws {
        let stack = try await S2Kit.stack()
        Self.requireSendable(stack.programs)
        Self.requireSendable(stack.exercises)
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask { try await stack.exercises.all().count }
            group.addTask { try await stack.programs.active() == nil ? 0 : 1 }
            return try await group.reduce(0, +)
        }
        #expect(counts == 8)
    }

    /// Sixteen edits of one program, all different.
    static func edits(of program: Program) throws -> [Program] {
        try (0 ..< 16).map { index in
            var days = program.days
            days[index % days.count].slots.removeLast(index % 3)
            days[(index + 1) % days.count].slots[0] = try days[(index + 1) % days.count].slots[0]
                .with(sets: 1 + index % 12)
            return try program.rebuilt(days: index.isMultiple(of: 5) ? days.reversed() : days, name: "Edit \(index)")
        }
    }

    @Test("Sixteen racing saves of one program leave exactly one of them, with exactly its rows")
    func racingSaves_leaveOneWholeProgram() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 4, days: 4, slotsPerDay: 4)
        try await stack.programs.save(program)
        let edits = try Self.edits(of: program)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for edit in edits {
                group.addTask { try await stack.programs.save(edit) }
            }
            try await group.waitForAll()
        }
        let stored = try await stack.programs.active()
        let winner = edits.first { $0 == stored }
        #expect(winner != nil, "the stored program is none of the saves: \(String(describing: stored?.name))")
        if let winner {
            #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([winner]))
        }
    }

    @Test("Readers racing sixteen saves only ever see the original or one whole edit")
    func readersRacingSaves_seeWholePrograms() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 4, days: 4, slotsPerDay: 4)
        try await stack.programs.save(program)
        let edits = try Self.edits(of: program)
        let seen = try await withThrowingTaskGroup(of: [Program?].self) { group in
            for edit in edits {
                group.addTask {
                    try await stack.programs.save(edit)
                    return []
                }
                group.addTask { try await [stack.programs.active(), stack.programs.program(id: program.id)] }
            }
            return try await group.reduce([]) { $0 + $1 }
        }
        let allowed = [program] + edits
        #expect(seen.allSatisfy { read in allowed.contains { $0 == read } }, "a reader saw a partial program")
    }

    @Test("Eight racing `setActive` calls leave exactly one active program")
    func racingSetActive_leaveOneActive() async throws {
        let stack = try await S2Kit.stack()
        let programs = try (1 ... 8).map { try S2Kit.program($0, weeks: 2, days: 1, slotsPerDay: 1, isActive: false) }
        for program in programs {
            try await stack.programs.save(program)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for program in programs {
                group.addTask { try await stack.programs.setActive(program.id) }
                group.addTask { _ = try await stack.programs.active() }
            }
            try await group.waitForAll()
        }
        #expect(try await ProgramLifecycleAdversarialTests.activeCount(stack.queue) == 1)
        let active = try await stack.programs.active()
        #expect(try programs.map { try $0.withActive(true) }.contains { $0 == active })
    }
}
