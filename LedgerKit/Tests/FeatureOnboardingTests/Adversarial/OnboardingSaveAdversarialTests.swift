@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2 adversarial round 1, criteria 4 to 6: what "Start training" and "Skip setup" save is the block the
/// Domain's generator writes for the picks, from the stored settings and catalog and the injected date, calendar
/// and ids. The expected block is always `ProgramTemplates.program` called here with those inputs.
@Suite("Adversarial F08 S2 · the program that is saved", .timeLimit(.minutes(1)))
struct OnboardingSaveAdversarialTests {
    /// A moment whose day differs between its own zone and UTC, with the week start that makes the two disagree
    /// about the week, and the first day of the week the zone's own calendar gives.
    nonisolated struct Moment: Sendable, CustomStringConvertible {
        let zone: String
        /// The instant, as `Fixtures.date` gives it in UTC.
        let instant: Date
        let weekStart: Weekday
        /// The first day of the week in the zone's own calendar, as ISO 8601.
        let expected: String

        var description: String {
            "\(zone), week from \(weekStart)"
        }

        /// Saturday 23:30 in Pago Pago (UTC−11) is Sunday 10:30 UTC: the Sunday week began on the 13th there.
        static let pagoPagoSaturdayNight = Moment(
            zone: "Pacific/Pago_Pago",
            instant: Fixtures.date(2026, 9, 20, hour: 10, minute: 30),
            weekStart: .sunday,
            expected: "2026-09-13"
        )
        /// Sunday 23:30 in Honolulu (UTC−10) is Monday 09:30 UTC: the Monday week began on the 14th there.
        static let honoluluSundayNight = Moment(
            zone: "Pacific/Honolulu",
            instant: Fixtures.date(2026, 9, 21, hour: 9, minute: 30),
            weekStart: .monday,
            expected: "2026-09-14"
        )
        /// Monday 00:30 in Kiritimati (UTC+14) is Sunday 10:30 UTC: the Monday week has just begun there.
        static let kiritimatiMondayMorning = Moment(
            zone: "Pacific/Kiritimati",
            instant: Fixtures.date(2026, 9, 20, hour: 10, minute: 30),
            weekStart: .monday,
            expected: "2026-09-21"
        )
    }

    @Test(
        "Start training saves the generator's block for the picks: one, active, eight weeks, the last a deload",
        arguments: TrainingGoal.allCases, DaysPerWeek.allCases
    )
    func startTraining_everyPick_savesTheGeneratorsBlock(goal: TrainingGoal, days: DaysPerWeek) async throws {
        let scene = try AdversarialScene(.seeded())
        await scene.store.loadUnits()
        scene.walk(goal: goal, days: days)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: goal, days: days)
        let saved = try #require(scene.programs.saved.first)
        #expect(saved.goal == goal)
        #expect(saved.daysPerWeek == days.rawValue)
        #expect(saved.name == BriefCopy.programNames[days])
        #expect(saved.weeks.map(\.isDeload) == Array(repeating: false, count: 7) + [true])
        // Fixtures.now is Wednesday 2026-09-16 and the default week starts on Monday (brief criterion 11).
        #expect(saved.startDate == CivilDate(year: 2026, month: 9, day: 14))
    }

    @Test(
        "Kilograms, the stored week start and the injected zone decide the block, late at night far from UTC",
        arguments: [Moment.pagoPagoSaturdayNight, .honoluluSundayNight, .kiritimatiMondayMorning]
    )
    func startTraining_kilogramsFarFromUTC_startsOnTheZonesWeek(_ moment: Moment) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: moment.zone))
        // The calendar's own first weekday is the other one: only the stored setting may decide.
        calendar.firstWeekday = moment.weekStart == .sunday ? 2 : 1
        var settings = Fixtures.settingsKg
        settings.weekStart = moment.weekStart
        var setup = try AdversarialScene.Setup.seeded(settings)
        setup.calendar = calendar
        setup.now = moment.instant
        let scene = AdversarialScene(setup)
        await scene.store.loadUnits()
        scene.walk(goal: .hypertrophy, days: .five)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .hypertrophy, days: .five)
        let saved = try #require(scene.programs.saved.first)
        #expect(saved.startDate == CivilDate(iso8601: moment.expected))
        #expect(saved.startDate.weekday == moment.weekStart)
        let catalog = try Dictionary(uniqueKeysWithValues: ExerciseCatalog.seed().map { ($0.id, $0) })
        let slots = saved.days.flatMap(\.slots)
        #expect(slots.allSatisfy { $0.startLoad == catalog[$0.exerciseID]?.startLoad(in: .kg) })
        #expect(slots.contains { $0.startLoad != catalog[$0.exerciseID]?.startLoad(in: .lb) }, "control")
    }
}

/// Calendars that are not Gregorian, a stored catalog that differs, a date years away, and Skip setup.
extension OnboardingSaveAdversarialTests {
    @Test(
        "A device calendar that is not Gregorian still starts the block on the Gregorian week",
        arguments: [Calendar.Identifier.buddhist, .islamicUmmAlQura, .japanese, .hebrew, .persian]
    )
    func startTraining_calendarIsNotGregorian_startsOnTheGregorianWeek(_ kind: Calendar.Identifier) async throws {
        var calendar = Calendar(identifier: kind)
        calendar.timeZone = Fixtures.utc
        var setup = try AdversarialScene.Setup.seeded()
        setup.calendar = calendar
        let scene = AdversarialScene(setup)
        scene.walk(goal: .both, days: .four)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .both, days: .four)
        #expect(scene.programs.saved.first?.startDate == CivilDate(year: 2026, month: 9, day: 14))
    }

    @Test("The start loads are the stored catalog's, where it differs from the bundled one")
    func startTraining_storedCatalogDiffers_usesTheStored() async throws {
        var catalog = try ExerciseCatalog.seed()
        let index = try #require(catalog.firstIndex { $0.name == "Barbell Bench Press" })
        catalog[index].defaultStartLoad = [.lb: .pounds(135), .kg: .kilograms(60)]
        let scene = AdversarialScene(.init(seed: .init(catalog: catalog)))
        await scene.store.loadUnits()
        scene.walk(goal: .both, days: .four)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .both, days: .four)
        let bench = scene.programs.saved.flatMap(\.days).flatMap(\.slots).filter { $0.exerciseID == catalog[index].id }
        #expect(!bench.isEmpty)
        #expect(bench.allSatisfy { $0.startLoad == .pounds(135) })
    }

    @Test("The injected date decides the week, years away from the machine's clock")
    func startTraining_injectedDateYearsAway_startsOnItsWeek() async throws {
        var setup = try AdversarialScene.Setup.seeded()
        setup.now = Fixtures.date(2031, 3, 5, hour: 12)
        let scene = AdversarialScene(setup)
        scene.walk(goal: .consistency, days: .three)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .consistency, days: .three)
        #expect(scene.programs.saved.first?.startDate == CivilDate(year: 2031, month: 3, day: 3))
    }

    @Test(
        "Skip setup saves both × four days from any step, whatever is picked, in the stored unit and week",
        arguments: 0 ... 2, [Units.lb, .kg]
    )
    func skipSetup_anyStepAnyPick_savesTheDefault(advances: Int, units: Units) async throws {
        var settings = Settings.default
        settings.units = units
        settings.weekStart = .sunday
        let scene = try AdversarialScene(.seeded(settings))
        await scene.store.loadUnits()
        scene.store.send(.pickGoal(.strength))
        if advances >= 1 {
            scene.store.send(.advance)
            scene.store.send(.pickDays(.six))
        }
        if advances == 2 {
            scene.store.send(.advance)
        }
        #expect(scene.store.state.step.rawValue == advances)
        await scene.tap(.skipSetup)
        try await scene.expectOneProgram(goal: .both, days: .four)
        let saved = try #require(scene.programs.saved.first)
        #expect(saved.goal == .both)
        #expect(saved.daysPerWeek == 4)
        #expect(saved.name == "Upper / Lower")
        #expect(saved.startDate == CivilDate(year: 2026, month: 9, day: 13), "Sunday before Fixtures.now")
        #expect(saved.days.map(\.name).first == "Upper A — Push focus")
    }

    @Test("The block is saved in the stored unit even when the screen has not read the settings yet")
    func startTraining_unitsNeverLoaded_savesInTheStoredUnit() async throws {
        let scene = try AdversarialScene(.seeded(Fixtures.settingsKg))
        scene.walk(goal: .strength, days: .six)
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .strength, days: .six)
    }

    @Test("Nothing is saved before a tap: the root's tasks alone, and every step of the walk, write nothing")
    func noTap_tasksAndWalk_saveNothing() async throws {
        let scene = try AdversarialScene(.seeded())
        await scene.store.loadUnits()
        await scene.runSave()
        scene.walk(goal: .strength, days: .three)
        await scene.runSave()
        scene.store.send(.back)
        scene.store.send(.back)
        await scene.runSave()
        #expect(scene.programs.offered.isEmpty)
        #expect(scene.store.attempt == nil)
        #expect(scene.ids.all.isEmpty, "no id is drawn before a save")
        #expect(scene.journal.all.allSatisfy { $0 == "settings.load" }, "\(scene.journal.all)")
        #expect(try await scene.stores.programs.active() == nil)
    }
}
