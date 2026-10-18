import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// What onboarding does with `ProgramTemplates` (F08), on a real database: the catalog is seeded, the program
/// is written over the exercises as stored, saved, and read back equal. Every slot names a stored exercise,
/// and every start load and the civil start date survive storage exactly (ADR-007).
@Suite("Template programs · GRDB round trip", .tags(.persistence), .timeLimit(.minutes(1)))
struct TemplateProgramRoundTripTests {
    /// One generated block; a failing case is named by it.
    struct Block: Sendable, CustomStringConvertible {
        let goal: TrainingGoal
        let days: DaysPerWeek
        let units: Units

        var description: String {
            "\(goal.rawValue) × \(days.rawValue) days, \(units.rawValue)"
        }

        /// The 16 (goal, days) pairs in each unit.
        static let all: [Block] = Units.allCases.flatMap { units in
            TrainingGoal.allCases.flatMap { goal in
                DaysPerWeek.allCases.map { Block(goal: goal, days: $0, units: units) }
            }
        }

        /// The block over `catalog`, starting on Monday 2026-09-14, with ids 1, 2, 3 … after the program's own.
        func program(catalog: [Exercise]) throws -> Program {
            let start = try #require(CivilDate(year: 2026, month: 9, day: 14))
            var number = 0
            return try ProgramTemplates.program(
                ProgramTemplates.Request(goal: goal, days: days, units: units, startDate: start),
                catalog: catalog,
                id: ProgramID(EventBuilders.uuid(0xF08)),
                newID: {
                    number += 1
                    return EventBuilders.uuid(number)
                }
            )
        }
    }

    @Test("A generated program saved to GRDB reads back equal, and is the active one", arguments: Block.all)
    func templateProgram_savedToGRDB_roundTripsEqual(block: Block) async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        let program = try await block.program(catalog: repositories.exercises.all())
        try await repositories.programs.save(program)
        #expect(try await repositories.programs.active() == program)
        #expect(try await repositories.programs.program(id: program.id) == program)
        // One row per week, day and slot, and no miss.
        let slots = program.days.flatMap(\.slots).count
        #expect(try await repositories.texts(ProgramRepositoryTests.liveCounts) == [
            "1 8 \(block.days.rawValue) \(slots) 0"
        ])
        let root = "SELECT start_date || ' ' || goal || ' ' || days_per_week || ' ' || is_active FROM program"
        #expect(try await repositories.texts(root) == ["2026-09-14 \(block.goal.rawValue) \(block.days.rawValue) 1"])
    }

    @Test("Written over the stored catalog, a program equals the one written over the bundled catalog")
    func templateProgram_storedCatalog_givesTheBundledCatalogsProgram() async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        let block = Block(goal: .both, days: .four, units: .kg)
        let stored = try await block.program(catalog: repositories.exercises.all())
        #expect(try stored == block.program(catalog: ExerciseCatalog.seed()))
    }

    @Test("Before the catalog is seeded there is no exercise to name: the generator throws, nothing is saved")
    func templateProgram_unseededCatalog_throwsUnknownExercise() async throws {
        let repositories = try Repositories()
        let stored = try await repositories.exercises.all()
        #expect(stored.isEmpty)
        #expect(throws: ProgramTemplateError.unknownExercise("Barbell Bench Press")) {
            try Block(goal: .both, days: .four, units: .lb).program(catalog: stored)
        }
        #expect(try await repositories.programs.active() == nil)
    }
}
