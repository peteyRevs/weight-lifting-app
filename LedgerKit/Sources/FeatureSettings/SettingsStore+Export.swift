import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain

/// "Export data · CSV" (F14 S2, criterion 5, N16): the log as a file the share sheet asks for when the lifter picks
/// where it goes. The file holds every stored workout this version can read, oldest first, in the units on screen,
/// and is named for the day it is written in the lifter's calendar. A workout whose rows cannot be read is left out,
/// and logged, as the History list leaves it out (`WorkoutRepository.workouts(in:)`).
extension SettingsStore {
    /// The export of the log in `units`, written when the share sheet asks for it. Its name for the share sheet is
    /// today's at this redraw; the file's own is the day it is written.
    func export(in units: Units) -> WorkoutExport {
        Self.export(
            ExportRequest(
                units: units,
                calendar: calendar,
                locale: locale,
                directory: exportDirectory,
                date: date
            ),
            from: workouts,
            through: exportWriter,
            logger: logger
        )
    }

    /// Made outside the main actor, so the file is read and written where the system's sheet calls it, never on the
    /// main actor, and one at a time (`ExportWriter`). The workouts' store is read only then: drawing Settings needs
    /// none. A failure is logged here, and the system's sheet reports it (ruling A2).
    nonisolated static func export(
        _ request: ExportRequest,
        from workouts: Dependency<any WorkoutRepository>,
        through writer: ExportWriter,
        logger: LedgerLogger
    ) -> WorkoutExport {
        WorkoutExport(fileName: request.plan().name, units: request.units) {
            do {
                let all = try await workouts.wrappedValue.workouts(in: Date.distantPast ..< Date.distantFuture)
                return try await writer.write(all, as: request.plan())
            } catch {
                logger.log.error("The export could not be written: \(String(describing: error))")
                throw error
            }
        }
    }

    /// Empties the export's directory when Settings goes away (N16), so no copy of the log stays on the phone; after
    /// any export still being written, never under it.
    func clearExports() async {
        do {
            try await exportWriter.clear(exportDirectory)
        } catch {
            logger.log.error("The export's directory could not be emptied: \(String(describing: error))")
        }
    }
}

/// What an export needs to name and write its file, read on the main actor when the export is made.
nonisolated struct ExportRequest: Sendable {
    let units: Units
    let calendar: Calendar
    let locale: Locale
    let directory: URL
    let date: DateGenerator

    /// The file as written now: named for today (F14-S2 G3 N3: Settings left open past midnight names the file for
    /// the day it is written).
    func plan() -> ExportFile.Plan {
        let day = CivilDate(date.now, in: calendar)?.description ?? ""
        return ExportFile.Plan(
            name: SettingsCopy.exportFileName(day, locale: locale),
            units: units,
            calendar: calendar,
            directory: directory
        )
    }
}
