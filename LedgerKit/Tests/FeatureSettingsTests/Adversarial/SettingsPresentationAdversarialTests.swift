@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import Testing

/// F14 S1a, G2: the presentation away from en_US and a tidy bundle: weekdays under non-Gregorian calendars and
/// a Saturday week start (N4), the rest in words in another language, and About values with stray spaces (N6).
@Suite("SettingsPresentation, adversarial", .tags(.feature))
struct SettingsPresentationAdversarialTests {
    static func model(
        _ settings: Settings = .default,
        about: AppAbout = SettingsFixtures.about,
        locale: Locale = Fixtures.locale,
        calendar: Calendar = Fixtures.calendar
    ) -> SettingsModel {
        SettingsPresentation.make(SettingsInput(settings: settings, about: about, locale: locale, calendar: calendar))
    }

    static func calendar(_ identifier: Calendar.Identifier, locale: String) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    @Test(
        "N4. Seven distinct days from the calendar's first weekday, under other calendars and week starts",
        arguments: [
            (Calendar.Identifier.persian, "fa_IR", Weekday.saturday),
            (.islamicUmmAlQura, "ar_SA", .sunday),
            (.gregorian, "ar_AE", .monday),
            (.hebrew, "he_IL", .sunday),
            (.japanese, "ja_JP", .sunday)
        ]
    )
    func weekdays_underOtherCalendars(identifier: Calendar.Identifier, locale: String, first: Weekday) {
        let calendar = Self.calendar(identifier, locale: locale)
        let model = Self.model(locale: Locale(identifier: locale), calendar: calendar)
        let days = model.weekStart.days
        #expect(days.count == 7)
        #expect(Set(days.map(\.id)).count == 7)
        #expect(Set(days.map(\.title)).count == 7, "every day has a name of its own")
        #expect(days.first?.id == first.rawValue)
        #expect(days.first?.action == .setWeekStart(first))
        #expect(model.weekStart.selected == Weekday.monday.rawValue)
        #expect(days.first { $0.id == model.weekStart.selected }?.title == model.weekStart.value)
    }

    @Test(
        "Criterion 2. The rest in words follows the lifter's language",
        arguments: [
            (30, "en_US", ["30 seconds"]), (90, "en_US", ["1 minute", "30 seconds"]), (300, "en_US", ["5 minutes"]),
            (90, "de_DE", ["1 Minute", "30 Sekunden"]), (120, "fr_FR", ["2 minutes"])
        ]
    )
    func spokenRest_inTheLocale(seconds: Int, locale: String, words: [String]) throws {
        let rest = try #require(RestDuration(seconds: seconds))
        let spoken = SettingsPresentation.spoken(rest, locale: Locale(identifier: locale))
        // The words, not ICU's joining ("und", ","), which may change between releases.
        #expect(words.allSatisfy(spoken.contains), "\(spoken)")
    }

    /// F14-S1-7 (cosmetic). `present(_:)` treats a blank value as missing, but keeps the spaces around a value
    /// that is not blank, so a padded bundle value draws double spaces.
    @Test("F14-S1-7. About values are drawn without the spaces around them")
    func about_trimsItsValues() {
        let line = Self.model(about: AppAbout(name: "App ", version: " 1.2.3", build: "45\n")).about
        #expect(line == "App 1.2.3 · build 45")
    }
}
