import Foundation
@testable import LedgerDomain
import Testing

/// F14 S1, N3 (decision #15; Pete's question 2, A): a new install's settings come from its region, the units from
/// the locale's measurement system and the week start from the calendar's first weekday; nothing else moves.
@Suite("Settings.regional", .tags(.domain))
struct SettingsRegionalTests {
    /// A Gregorian calendar as the region `identifier` sets it up.
    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: identifier)
        return calendar
    }

    static func regional(_ identifier: String) -> Settings {
        .regional(locale: Locale(identifier: identifier), calendar: calendar(identifier))
    }

    @Test("The United States: pounds, and weeks that start on Sunday")
    func unitedStates_poundsAndSunday() {
        let settings = Self.regional("en_US")
        #expect(settings.units == .lb)
        #expect(settings.weekStart == .sunday)
    }

    @Test("Germany and the United Kingdom: kilograms, and weeks that start on Monday", arguments: ["de_DE", "en_GB"])
    func europe_kilogramsAndMonday(_ identifier: String) {
        let settings = Self.regional(identifier)
        #expect(settings.units == .kg)
        #expect(settings.weekStart == .monday)
    }

    @Test("The United Arab Emirates: kilograms, and the calendar's own first weekday")
    func emirates_kilogramsAndTheCalendarsFirstWeekday() {
        let calendar = Self.calendar("ar_AE")
        let settings = Settings.regional(locale: Locale(identifier: "ar_AE"), calendar: calendar)
        #expect(settings.units == .kg)
        #expect(settings.weekStart == Weekday(calendarWeekday: calendar.firstWeekday))
    }

    @Test("Only the units and the week start come from the region; the rest is the defaults")
    func everythingElse_isTheDefaults() {
        var settings = Self.regional("de_DE")
        settings.units = Settings.default.units
        settings.weekStart = Settings.default.weekStart
        #expect(settings == .default)
    }
}
