@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import Testing

/// F14 S1: what Settings draws and speaks, from a fixed input: the rows in pounds and in kilograms, the rest and its
/// bounds (criterion 2), the weekdays per locale (N4), the switches (criterion 8), the Health row (criterion 4, Q4)
/// and the About line (N6).
@Suite("SettingsPresentation", .tags(.feature))
struct SettingsPresentationTests {
    static func input(
        _ settings: Settings = .default,
        about: AppAbout = SettingsFixtures.about,
        locale: Locale = Fixtures.locale,
        calendar: Calendar = Fixtures.calendar
    ) -> SettingsInput {
        SettingsInput(settings: settings, about: about, locale: locale, calendar: calendar)
    }

    static func model(_ settings: Settings = .default) -> SettingsModel {
        SettingsPresentation.make(input(settings))
    }

    static func settings(_ change: (inout Settings) -> Void) -> Settings {
        var settings = Settings.default
        change(&settings)
        return settings
    }

    @Test("The headings, the titles and their lines, in the page's order")
    func page_namesEveryRow() {
        let model = Self.model()
        #expect(model.title == "Settings")
        #expect(model.problem == nil)
        #expect(model.training == "TRAINING" && model.data == "DATA")
        #expect([model.units.title, model.rest.title, model.weekStart.title] == [
            "Units", "Default rest", "Week starts on"
        ])
        #expect([model.units.detail, model.rest.detail, model.weekStart.detail] == [
            "Applies to every log and chart", "Used for new exercises", "For the week strip and the week's totals"
        ])
        #expect(model.switches.map(\.title) == ["Plate math", "Auto rest timer", "Watch haptic at zero"])
        #expect(model.switches.map(\.detail) == [
            "Show the plates per side on each set", "Start the clock when a set is logged",
            "Buzz the wrist when rest ends"
        ])
    }

    @Test("Criterion 1, N5. Units: LB then KG, read as pounds and kilograms, the stored one selected", arguments: [
        Units.lb, .kg
    ])
    func units_twoOptions_theStoredSelected(_ units: Units) {
        let options = Self.model(Self.settings { $0.units = units }).units.options
        #expect(options.map(\.title) == ["LB", "KG"])
        #expect(options.map(\.spokenLabel) == ["pounds", "kilograms"])
        #expect(options.map(\.isSelected) == [units == .lb, units == .kg])
        #expect(options.map(\.action) == [.setUnits(.lb), .setUnits(.kg)])
    }

    @Test("Criterion 2. The rest reads as the Day editor writes it, and in words", arguments: [
        (90, "1:30", "1 minute, 30 seconds"), (120, "2 min", "2 minutes"), (45, "45s", "45 seconds"),
        (300, "5 min", "5 minutes")
    ])
    func rest_drawnAndSpoken(seconds: Int, drawn: String, spoken: String) {
        let rest = Self.model(Self.settings { $0.defaultRest = RestDuration(clampingSeconds: seconds) }).rest
        #expect(rest.value == drawn)
        #expect(rest.spokenValue == spoken)
    }

    @Test("Criterion 2. Each step moves the rest 15 s; the step past 30 s or 300 s is switched off")
    func rest_stepsWithinItsBounds() {
        let middle = Self.model().rest
        #expect(middle.decrement == .setDefaultRest(RestDuration(clampingSeconds: 75)))
        #expect(middle.increment == .setDefaultRest(RestDuration(clampingSeconds: 105)))
        let shortest = Self.model(Self.settings { $0.defaultRest = RestDuration(clampingSeconds: 30) }).rest
        #expect(shortest.decrement == nil)
        #expect(shortest.increment == .setDefaultRest(RestDuration(clampingSeconds: 45)))
        let longest = Self.model(Self.settings { $0.defaultRest = RestDuration(clampingSeconds: 300) }).rest
        #expect(longest.decrement == .setDefaultRest(RestDuration(clampingSeconds: 285)))
        #expect(longest.increment == nil)
    }

    @Test("N4. The seven weekdays, named in the locale, from the calendar's first weekday, the stored one chosen")
    func weekStart_listedFromTheFirstWeekday() {
        let sunday = SettingsPresentation.make(Self.input(Self.settings { $0.weekStart = .wednesday }))
        #expect(sunday.weekStart.days.map(\.title) == [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ])
        #expect(sunday.weekStart.value == "Wednesday")
        #expect(sunday.weekStart.selected == Weekday.wednesday.rawValue)
        #expect(sunday.weekStart.days.first?.action == .setWeekStart(.sunday))
        var monday = Fixtures.calendar
        monday.firstWeekday = 2
        let french = SettingsPresentation.make(Self.input(locale: Locale(identifier: "fr_FR"), calendar: monday))
        #expect(french.weekStart.days.map(\.title).first == "lundi")
        #expect(french.weekStart.days.map(\.id) == [1, 2, 3, 4, 5, 6, 7])
        #expect(french.weekStart.value == "lundi")
    }

    @Test("Criterion 8. Each switch shows its state and turns it over", arguments: [true, false])
    func switches_showTheirStateAndTurnIt(_ isOn: Bool) {
        let model = Self.model(Self.settings {
            $0.plateMathEnabled = isOn
            $0.autoRest = !isOn
            $0.watchBuzz = isOn
        })
        #expect(model.switches.map(\.isOn) == [isOn, !isOn, isOn])
        #expect(model.switches.map(\.action) == [.setPlateMath(!isOn), .setAutoRest(isOn), .setWatchBuzz(!isOn)])
    }

    @Test("Criterion 4 (Q4, A). The Health row reads Apple Health, Not connected, and does nothing")
    func health_isNotConnected() {
        #expect(Self.model().health == SettingsModel.Status(title: "Apple Health", value: "Not connected"))
    }

    @Test("N7. Debug builds have the Diagnostics row, which asks for the Debug menu")
    func diagnostics_inDebug() {
        #expect(Self.model().diagnostics == SettingsModel.Link(title: "Diagnostics", action: .route(.debugMenu)))
    }

    @Test("A failed save shows its line under the title")
    func saveFailed_showsTheLine() {
        var input = Self.input()
        input.saveFailed = true
        #expect(SettingsPresentation.make(input).problem == "Couldn't save that change.")
    }

    @Test(
        "N6. The About line: name, version and build, and each missing part left out, never without words",
        arguments: [
            (AppAbout(name: "App", version: "1.2.3", build: "45"), "App 1.2.3 · build 45"),
            (AppAbout(name: nil, version: "1.2.3", build: "45"), "Version 1.2.3 · build 45"),
            (AppAbout(name: "App", version: nil, build: "45"), "App · build 45"),
            (AppAbout(name: "App", version: "1.2.3", build: nil), "App 1.2.3"),
            (AppAbout(name: nil, version: nil, build: "45"), "build 45"),
            (AppAbout(name: "App", version: nil, build: nil), "App · Version unknown"),
            (AppAbout(name: nil, version: nil, build: nil), "Version unknown"),
            (AppAbout(name: " ", version: "", build: "\n"), "Version unknown")
        ]
    )
    func about_leavesOutWhatIsMissing(about: AppAbout, line: String) {
        #expect(SettingsPresentation.make(Self.input(about: about)).about == line)
    }
}
