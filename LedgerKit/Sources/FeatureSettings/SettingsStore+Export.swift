import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain

/// "Export data · CSV" (F14 S2, criterion 5, N16): the log as a file the share sheet asks for when the lifter picks
/// where it goes. The file holds every stored workout, oldest first, in the units on screen, and is named for today
/// in the lifter's calendar.
extension SettingsStore {
    /// The export of the log in `units`, written when the share sheet asks for it.
    func export(in units: Units) -> WorkoutExport {
        let day = CivilDate(date.now, in: calendar)?.description ?? ""
        let plan = ExportFile.Plan(
            name: SettingsCopy.exportFileName(day, locale: locale),
            units: units,
            calendar: calendar,
            directory: exportDirectory
        )
        return Self.export(plan, from: workouts, logger: logger)
    }

    /// Made outside the main actor, so the file is read and written where the system's sheet calls it, never on the
    /// main actor. The workouts' store is read only then: drawing Settings needs none. A failure is logged here, and
    /// the system's sheet reports it (ruling A2).
    nonisolated static func export(
        _ plan: ExportFile.Plan,
        from workouts: Dependency<any WorkoutRepository>,
        logger: LedgerLogger
    ) -> WorkoutExport {
        WorkoutExport(fileName: plan.name, units: plan.units) {
            do {
                let all = try await workouts.wrappedValue.workouts(in: Date.distantPast ..< Date.distantFuture)
                return try ExportFile.write(all, as: plan)
            } catch {
                logger.log.error("The export could not be written: \(String(describing: error))")
                throw error
            }
        }
    }

    /// Empties the export's directory when Settings goes away (N16), so no copy of the log stays on the phone.
    func clearExports() {
        do {
            try ExportFile.clear(exportDirectory)
        } catch {
            logger.log.error("The export's directory could not be emptied: \(String(describing: error))")
        }
    }
}
