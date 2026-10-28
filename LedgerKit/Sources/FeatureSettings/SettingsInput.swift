import Foundation
import LedgerDomain

/// What `SettingsPresentation.make(_:)` reads. The store fills it; the presentation reaches for nothing else, so
/// the same input always gives the same model.
nonisolated struct SettingsInput: Sendable {
    /// The settings as the lifter sees them: a change not yet saved, else the stored ones, else (a row this app
    /// cannot read) `Settings.default`.
    var settings: Settings
    var about: AppAbout
    /// The last change could not be saved.
    var saveFailed = false
    /// The weekdays are named in this locale, and listed from this calendar's first weekday.
    var locale: Locale
    var calendar: Calendar
}
