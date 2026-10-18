import Foundation

/// A UI test's program (F08, ruling R2): `-LEDGER_UITEST_PROGRAM seed` beside `-LEDGER_UITEST` saves the spec's
/// seed program (`Fixtures.seedProgram()`, through `SampleProgram`) as the active one once the launch's first
/// pass has run, when there is no active program, so that the root opens on the tabs. It exists because a
/// fresh UI-test database has no program, and opens on onboarding: the tests that are not about onboarding
/// read the seed program's weeks and loads, which "Skip setup" would not save.
///
/// Read as `UITestSaveFailures` reads its argument, and like it **in Debug builds only**: a Release build reads
/// no argument here and saves nothing.
nonisolated enum UITestProgram {
    static let argument = "-LEDGER_UITEST_PROGRAM"
    /// The one value the argument takes.
    static let seed = "seed"

    /// The argument is there and its value is missing or is not `seed`.
    struct InvalidValue: Error, Equatable {
        let value: String?
    }

    /// Whether the arguments ask for the seed program; false when they do not, or are not a UI test's.
    static func seeds(arguments: [String]) throws -> Bool {
        guard arguments.contains("-LEDGER_UITEST"), let index = arguments.firstIndex(of: argument) else {
            return false
        }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        guard value == seed else {
            throw InvalidValue(value: value)
        }
        return true
    }

    /// `seeds(arguments:)` for this launch. A value that cannot be read stops the launch, as a wrong date does.
    static func liveSeeds(arguments: [String]) -> Bool {
        #if DEBUG
            do {
                return try seeds(arguments: arguments)
            } catch {
                fatalError("\(argument) takes one value, \(seed): \(error)")
            }
        #else
            return false
        #endif
    }
}
