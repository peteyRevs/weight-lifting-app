import Foundation
@testable import LedgerDomain
import Testing

/// One block the generator is asked for. A failing parameterized test names its case.
struct TemplateCase: Sendable, CustomStringConvertible {
    let goal: TrainingGoal
    let days: DaysPerWeek
    var units: Units = .lb

    var description: String {
        "\(goal.rawValue) × \(days.rawValue) days, \(units.rawValue)"
    }

    /// The 16 (goal, days) pairs, in pounds.
    static let pairs: [TemplateCase] = TrainingGoal.allCases.flatMap { goal in
        DaysPerWeek.allCases.map { TemplateCase(goal: goal, days: $0) }
    }

    /// The 16 pairs in each unit.
    static let all: [TemplateCase] = Units.allCases.flatMap { units in
        pairs.map { TemplateCase(goal: $0.goal, days: $0.days, units: units) }
    }

    /// Monday 2026-09-14: the first day of the week that holds `Fixtures.now`, weeks starting on Monday.
    static let start = Fixtures.civil(2026, 9, 14)

    var request: ProgramTemplates.Request {
        ProgramTemplates.Request(goal: goal, days: days, units: units, startDate: Self.start)
    }

    /// The block for this case over `catalog` (the bundled one when `nil`): its id is `Fixtures.programID`, and
    /// the ids the generator asks for are `Fixtures.uuid(firstID)`, `uuid(firstID + 1)` … in the order asked.
    func program(catalog: [Exercise]? = nil, firstID: Int = 1) throws -> Program {
        var next = firstID
        return try ProgramTemplates.program(
            request,
            catalog: catalog ?? BundledCatalog.exercises(),
            id: Fixtures.programID,
            newID: {
                defer { next += 1 }
                return Fixtures.uuid(next)
            }
        )
    }
}

/// The bundled exercise catalog, decoded once for the template suites.
enum BundledCatalog {
    private static let seed = Result { try ExerciseCatalog.seed() }

    static func exercises() throws -> [Exercise] {
        try seed.get()
    }

    static func byID() throws -> [ExerciseID: Exercise] {
        try Dictionary(uniqueKeysWithValues: exercises().map { ($0.id, $0) })
    }
}
