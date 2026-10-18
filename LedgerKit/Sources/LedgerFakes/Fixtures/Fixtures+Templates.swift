#if DEBUG
    import Foundation
    import LedgerDomain

    public extension Fixtures {
        /// The id of `defaultProgram`: its own, so the two program fixtures are never one program to a store.
        static let defaultProgramID = ProgramID(uuid(9004))

        /// The program onboarding saves for a lifter who skips setup (F08): `both`, four days, in pounds,
        /// active, written by `ProgramTemplates` over the bundled catalog.
        ///
        /// It is spec §6.4's block, as `seedProgram` is, and differs from it in three ways only:
        /// - its start loads are the catalog's (Bench 45 lb, decision #21), where `seedProgram` keeps the
        ///   prototype's (Bench 180 lb);
        /// - it starts on `startDate`, by default the Monday of the week that holds `now` (2026-09-14), so
        ///   `now` is in its week 1, where `seedProgram` started four weeks earlier;
        /// - its ids are `defaultProgramID` and then `uuid(1001)`, `uuid(1002)` … in the generator's order:
        ///   the eight weeks, then each day followed by its slots.
        ///
        /// `history(weeks:)` and `seedSession()` are built from `seedProgram` and name its days and slots, so
        /// they do not belong beside this program.
        static func defaultProgram(startDate: CivilDate? = nil) throws -> Program {
            let weekStart = settingsLb.weekStart
            guard let start = startDate
                ?? ProgramTemplates.startDate(containing: now, weekStart: weekStart, calendar: calendar)
            else {
                throw Invalid(fixture: "defaultProgram.startDate")
            }
            var number = 1000
            return try ProgramTemplates.program(
                ProgramTemplates.Request(goal: .both, days: .four, units: settingsLb.units, startDate: start),
                catalog: ExerciseCatalog.seed(),
                id: defaultProgramID,
                newID: {
                    number += 1
                    return uuid(number)
                }
            )
        }
    }
#endif
