import Foundation
@testable import LedgerDomain
import Testing

/// F14 S1a, G2: N3's regional settings across the regions a lifter's iPhone can be set to. The units come from the
/// locale's measurement system (only `.us` is pounds), the week start from the calendar the region sets up. The
/// expected values are CLDR's, as Foundation reports them.
@Suite("Settings.regional, adversarial", .tags(.domain))
struct SettingsRegionalAdversarialTests {
    /// The region's own calendar (`Locale.calendar`), as `Calendar.autoupdatingCurrent` is on a device so set.
    static func regional(_ identifier: String) -> Settings {
        let locale = Locale(identifier: identifier)
        return .regional(locale: locale, calendar: locale.calendar)
    }

    @Test(
        "N3. Units and week start per region",
        arguments: [
            ("en_US", Units.lb, Weekday.sunday),
            ("en_GB", .kg, .monday), // the UK system is not the US one
            ("de_DE", .kg, .monday),
            ("fr_FR", .kg, .monday),
            ("ja_JP", .kg, .sunday),
            ("ar_SA", .kg, .sunday), // CLDR: Sunday in Saudi Arabia, under the Umm al-Qura calendar
            ("fa_IR", .kg, .saturday), // the Persian calendar's Saturday
            ("en_US@measure=metric", .kg, .sunday), // a US lifter who chose metric
            ("en_US@fw=mon", .lb, .monday), // a US lifter who chose Monday weeks
            ("en_001", .kg, .monday),
            ("en_LR", .lb, .monday), // Liberia measures in US units
            ("my_MM", .kg, .sunday)
        ]
    )
    func regional_perRegion(identifier: String, units: Units, weekStart: Weekday) {
        let settings = Self.regional(identifier)
        #expect(settings.units == units, "\(identifier)")
        #expect(settings.weekStart == weekStart, "\(identifier)")
    }

    @Test("N3. The week start is the calendar's, whatever the locale says")
    func weekStart_followsTheCalendar() {
        var sundays = Calendar(identifier: .gregorian)
        sundays.locale = Locale(identifier: "de_DE")
        sundays.firstWeekday = 1
        let settings = Settings.regional(locale: Locale(identifier: "de_DE"), calendar: sundays)
        #expect(settings.weekStart == .sunday)
        #expect(settings.units == .kg)
    }

    @Test("N3. Every first weekday a calendar can have becomes that weekday", arguments: 1 ... 7)
    func everyFirstWeekday_maps(firstWeekday: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        let settings = Settings.regional(locale: Locale(identifier: "en_001"), calendar: calendar)
        #expect(settings.weekStart.calendarWeekday == firstWeekday)
    }

    /// Recorded, not a defect on a device: a locale with no region (`en`, the root locale) measures in US units,
    /// so it seeds pounds. An iPhone always has a region.
    @Test("Pin. A locale with no region seeds pounds", arguments: ["en", "", "und"])
    func noRegion_seedsPounds(identifier: String) {
        #expect(Self.regional(identifier).units == .lb)
    }

    @Test("N3. Only the units and the week start move, in every region")
    func onlyTwoFieldsMove() {
        for identifier in ["en_US", "fa_IR", "ar_SA", "en_US@measure=metric"] {
            var settings = Self.regional(identifier)
            settings.units = Settings.default.units
            settings.weekStart = Settings.default.weekStart
            #expect(settings == .default, "\(identifier)")
        }
    }
}
