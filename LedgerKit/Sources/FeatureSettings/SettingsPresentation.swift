import Foundation
import LedgerDomain

/// Settings' logic and its words, in one pure step: `make(_:)` turns the settings the lifter sees into the screen.
/// Every text comes from `SettingsCopy`, but the rest's drawn value, which is the Domain's (`RestDuration.label`),
/// and the weekdays' names, which are the lifter's calendar's.
nonisolated enum SettingsPresentation {
    /// Between the About line's parts.
    static let separator = " · "
    /// The order of the units' options.
    static let unitsOrder: [LedgerDomain.Units] = [.lb, .kg]
    /// Rule 3: "Default rest" moves by 15 s.
    static let restStep = 15

    static func make(_ input: SettingsInput) -> SettingsModel {
        let settings = input.settings
        return SettingsModel(
            title: SettingsCopy.title,
            problem: input.saveFailed ? SettingsCopy.saveFailed : nil,
            training: SettingsCopy.training,
            units: units(settings.units),
            rest: rest(settings.defaultRest, locale: input.locale),
            weekStart: weekStart(settings.weekStart, locale: input.locale, calendar: input.calendar),
            switches: switches(settings),
            data: SettingsCopy.data,
            health: SettingsModel.Status(title: SettingsCopy.appleHealth, value: SettingsCopy.notConnected),
            diagnostics: diagnostics,
            about: about(input.about, locale: input.locale)
        )
    }

    static func units(_ chosen: LedgerDomain.Units) -> SettingsModel.Units {
        SettingsModel.Units(
            title: SettingsCopy.units,
            detail: SettingsCopy.unitsDetail,
            options: unitsOrder.enumerated().map { place, units in
                SettingsModel.Option(
                    id: place,
                    title: SettingsCopy.unitsOption(units),
                    spokenLabel: SettingsCopy.spokenUnits(units),
                    isSelected: units == chosen,
                    action: .setUnits(units)
                )
            }
        )
    }

    /// The rest, and a step either way that stays within 30–300 s (rule 3); a step past a bound is none.
    static func rest(_ rest: RestDuration, locale: Locale) -> SettingsModel.Rest {
        let shorter = RestDuration(seconds: rest.seconds - restStep)
        let longer = RestDuration(seconds: rest.seconds + restStep)
        return SettingsModel.Rest(
            title: SettingsCopy.defaultRest,
            detail: SettingsCopy.defaultRestDetail,
            value: rest.label,
            spokenValue: spoken(rest, locale: locale),
            decrement: shorter.map(SettingsAction.setDefaultRest),
            increment: longer.map(SettingsAction.setDefaultRest)
        )
    }

    /// "1 minute, 30 seconds", "2 minutes", "45 seconds": the rest in words, in `locale`.
    static func spoken(_ rest: RestDuration, locale: Locale) -> String {
        Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds], width: .wide)
            .locale(locale)
            .format(rest.duration)
    }

    /// The seven weekdays from the calendar's first, each named in the lifter's locale as it stands alone
    /// ("Monday", "lundi").
    static func weekStart(_ chosen: Weekday, locale: Locale, calendar: Calendar) -> SettingsModel.WeekStart {
        var named = calendar
        named.locale = locale
        let names = named.standaloneWeekdaySymbols
        let first = Weekday.first(of: calendar)
        let days = (0 ..< 7).compactMap { offset in
            Weekday(rawValue: (first.rawValue - 1 + offset) % 7 + 1)
        }.map { day in
            SettingsModel.Day(id: day.rawValue, title: names[day.calendarWeekday - 1], action: .setWeekStart(day))
        }
        return SettingsModel.WeekStart(
            title: SettingsCopy.weekStart,
            detail: SettingsCopy.weekStartDetail,
            value: names[chosen.calendarWeekday - 1],
            days: days,
            selected: chosen.rawValue
        )
    }

    static func switches(_ settings: Settings) -> [SettingsModel.Switch] {
        [
            SettingsModel.Switch(
                id: .plateMath,
                title: SettingsCopy.plateMath,
                detail: SettingsCopy.plateMathDetail,
                isOn: settings.plateMathEnabled,
                action: .setPlateMath(!settings.plateMathEnabled)
            ),
            SettingsModel.Switch(
                id: .autoRest,
                title: SettingsCopy.autoRest,
                detail: SettingsCopy.autoRestDetail,
                isOn: settings.autoRest,
                action: .setAutoRest(!settings.autoRest)
            ),
            SettingsModel.Switch(
                id: .watchBuzz,
                title: SettingsCopy.watchBuzz,
                detail: SettingsCopy.watchBuzzDetail,
                isOn: settings.watchBuzz,
                action: .setWatchBuzz(!settings.watchBuzz)
            )
        ]
    }

    /// "Diagnostics" in a Debug build (N7); a Release build has no row, and no route for it.
    static var diagnostics: SettingsModel.Link? {
        #if DEBUG
            SettingsModel.Link(title: SettingsCopy.diagnostics, action: .route(.debugMenu))
        #else
            nil
        #endif
    }

    /// "Ledger 0.14.0 · build 74" (N6). A part the bundle lacks is left out: "Version 0.14.0 · build 74" with no
    /// name, "Ledger · build 74" with no version; with neither a version nor a build, "Ledger · Version unknown"
    /// or "Version unknown", so the line always says what is known in words.
    static func about(_ about: AppAbout, locale: Locale) -> String {
        let name = present(about.name)
        let version = present(about.version)
        let head = name.map { name in [name, version].compactMap(\.self).joined(separator: " ") }
            ?? version.map { SettingsCopy.version($0, locale: locale) }
        let tail = present(about.build).map { SettingsCopy.build($0, locale: locale) }
        guard version != nil || tail != nil else {
            return [name, SettingsCopy.versionUnknown].compactMap(\.self).joined(separator: separator)
        }
        return [head, tail].compactMap(\.self).joined(separator: separator)
    }

    /// `text` without the spaces and line breaks around it, when anything is left (F14-S1-7).
    private static func present(_ text: String?) -> String? {
        text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
