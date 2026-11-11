import CoreTransferable
import LedgerDomain
import UniformTypeIdentifiers

/// The lifter's log as a file to share (F14 S2, criterion 5, N18; ruling A2): what "Export data · CSV"'s `ShareLink`
/// hands the system. The file is written only when the lifter picks where it goes (`FileRepresentation`), by `write`,
/// which the store makes (`SettingsStore.export`); a write that throws is reported by the system's sheet.
nonisolated struct WorkoutExport: Transferable, Equatable, Sendable {
    /// "workouts-2026-11-10.csv": the name the share sheet shows before the file exists.
    let fileName: String
    let units: Units
    /// Writes the file and returns where it is.
    let write: @Sendable () async throws -> URL

    /// Two exports are the same when they would write the same file: `write` is the store's, made over the same
    /// stores, so it is not compared.
    static func == (lhs: WorkoutExport, rhs: WorkoutExport) -> Bool {
        lhs.fileName == rhs.fileName && lhs.units == rhs.units
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            try await SentTransferredFile(export.write())
        }
    }

    /// An export that writes nothing, for an input that has none: the previews' and the presentation tests'.
    static let unavailable = WorkoutExport(fileName: "", units: .lb) {
        throw CocoaError(.fileWriteUnknown)
    }
}
