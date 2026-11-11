import Foundation
import LedgerDomain

/// Where and how the export's file is written (F14 S2, N15, N16): in a directory of its own under the temporary
/// directory, emptied before each export and when Settings goes away (`SettingsStore.run()`), so no copy of the log
/// is left behind; streamed workout by workout to a `FileHandle`, so the whole file is never one `String`; UTF-8 with a
/// byte-order mark, then `CSVExport`'s header and rows.
nonisolated enum ExportFile {
    /// What one export writes: the file's name, the unit of its weights, the calendar of its dates, and where.
    struct Plan: Sendable {
        let name: String
        let units: Units
        let calendar: Calendar
        let directory: URL
    }

    /// `temporaryDirectory/Export/`.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
    }

    /// Writes `workouts`, oldest first (of two that started together, the smaller id first), as `plan` says, to a new
    /// file in its directory, after emptying it, and returns the file. What throws is the file system's.
    static func write(_ workouts: [WorkoutState], as plan: Plan) throws -> URL {
        let units = plan.units
        try clear(plan.directory)
        try FileManager.default.createDirectory(at: plan.directory, withIntermediateDirectories: true)
        let file = plan.directory.appending(path: plan.name, directoryHint: .notDirectory)
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        let handle = try FileHandle(forWritingTo: file)
        do {
            try handle.write(contentsOf: Data((CSVExport.byteOrderMark + CSVExport.header(units: units)).utf8))
            for workout in workouts.sorted(by: isOlder) {
                try handle
                    .write(contentsOf: Data(CSVExport.lines(for: workout, units: units, calendar: plan.calendar).utf8))
            }
            try handle.close()
        } catch {
            // The write's error is the one to report; a close that fails after it adds nothing.
            try? handle.close()
            throw error
        }
        return file
    }

    /// Removes `directory` and everything in it; one that is not there is already empty.
    static func clear(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    private static func isOlder(_ first: WorkoutState, _ second: WorkoutState) -> Bool {
        first.startedAt == second.startedAt
            ? first.id.rawValue.uuidString < second.id.rawValue.uuidString
            : first.startedAt < second.startedAt
    }
}
