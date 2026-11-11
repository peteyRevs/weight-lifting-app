import Foundation
import LedgerDomain

/// The words of "Export data · CSV" (F14 S2, criterion 5).
nonisolated extension SettingsCopy {
    static var export: String {
        String(
            localized: "Export data · CSV",
            bundle: .module,
            comment: "Settings row: shares the whole log as a CSV file"
        )
    }

    /// What VoiceOver reads for the row: the dot is a pause.
    static var exportSpoken: String {
        String(
            localized: "Export data, CSV",
            bundle: .module,
            comment: "Spoken name of the Export data · CSV row in Settings"
        )
    }

    static var exportDetail: String {
        String(
            localized: "Every set you logged, in your current units",
            bundle: .module,
            comment: "Under Export data · CSV in Settings: what the file holds"
        )
    }

    /// "workouts-2026-11-10.csv": the file's name, which the lifter sees in the share sheet and in Files (Pete's
    /// question 5, A: no product name, so it never changes with one).
    static func exportFileName(_ day: String, locale: Locale) -> String {
        String(
            localized: "workouts-\(day).csv",
            bundle: .module,
            locale: locale,
            comment: "Name of the exported file, with the day as YYYY-MM-DD; keep it a valid file name ending in .csv"
        )
    }
}
