import FeatureWorkout
import Foundation
import LedgerDomain

/// A UI test's past workouts (F15 S1, criterion 1 as restated, Q1): `-LEDGER_UITEST_HISTORY <weeks>` beside
/// `-LEDGER_UITEST` and `-LEDGER_UITEST_PROGRAM seed` stores the seed program's finished workouts of the last `weeks`
/// weeks (`Fixtures.history(weeks:)`, through `SampleProgram`) right after the seed program is saved, when the
/// database holds no workout. It exists because a UI-test database has no workout, and the History list, an
/// exercise's chart and a finished set in other units each need some: logging them through the screens would take
/// half a minute each.
///
/// The workouts go through `WorkoutRepository.materialize`, as a finished workout does, so their records and stats
/// are derived as after real workouts (ruling A1). They are anchored to the fixture's own week (`Fixtures.now`,
/// Wednesday 2026-09-16), not to the app's clock: a test pairs this with `-LEDGER_UITEST_NOW` in that week.
///
/// Read as `UITestProgram` reads its argument, and like it **in Debug builds only**: a Release build reads no
/// argument here and stores nothing.
nonisolated enum UITestHistory {
    static let argument = "-LEDGER_UITEST_HISTORY"
    /// The weeks a value may ask for: at least one, and no more than two blocks of the seed program.
    static let weeks = 1 ... 16

    /// The argument is there and its value is missing or is no whole number of `weeks`.
    struct InvalidWeeks: Error, Equatable {
        let value: String?
    }

    /// The argument is there without `-LEDGER_UITEST_PROGRAM seed`: the fixture's workouts belong to the seed
    /// program, and a database without it would hold workouts of no program.
    struct NoSeedProgram: Error, Equatable {}

    /// How many weeks of workouts the arguments ask for; nil when they ask for none, or are not a UI test's.
    static func weeks(arguments: [String]) throws -> Int? {
        guard arguments.contains("-LEDGER_UITEST"), let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        guard let value, let count = Int(value), weeks.contains(count) else {
            throw InvalidWeeks(value: value)
        }
        guard (try? UITestProgram.seeds(arguments: arguments)) == true else {
            throw NoSeedProgram()
        }
        return count
    }

    /// `weeks(arguments:)` for this launch. A value that cannot be read stops the launch, as a wrong date does.
    static func liveWeeks(arguments: [String]) -> Int? {
        #if DEBUG
            do {
                return try weeks(arguments: arguments)
            } catch {
                fatalError("\(argument) takes 1 to 16 weeks, beside \(UITestProgram.argument) seed: \(error)")
            }
        #else
            return nil
        #endif
    }

    #if DEBUG
        /// Stores the seed program's workouts of the last `weeks` weeks in `workouts` when it holds no workout, and
        /// nothing otherwise: a second launch over the same database stores nothing more.
        static func saveIfEmpty(weeks: Int, in workouts: any WorkoutRepository) async throws {
            guard try await workouts.recent(limit: 1).isEmpty else {
                return
            }
            for workout in try SampleProgram.history(weeks: weeks) {
                try await workouts.materialize(workout, slotUpdates: [])
            }
        }
    #endif
}
