@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criteria 4, 5 and 6: the one program a save writes. It is the generator's, from the picks or, for
/// "Skip setup", the default; in the stored settings' unit; starting on the first day, per the settings' week
/// start, of the week that holds the injected date; over the stored catalog; with ids from the injected source.
@Suite("OnboardingStore: the program a save writes", .timeLimit(.minutes(1)))
struct OnboardingStoreSaveTests {
    @Test(
        "Start training saves one active program: the generator's, from the picks",
        arguments: [
            (TrainingGoal.both, DaysPerWeek.four), (.strength, .three), (.hypertrophy, .five), (.consistency, .six)
        ]
    )
    func startTraining_savesOneActiveProgram_fromThePicks(goal: TrainingGoal, days: DaysPerWeek) async throws {
        try await StoreScene.run { scene in
            scene.store.send(.pickGoal(goal))
            scene.store.send(.advance)
            scene.store.send(.pickDays(days))
            scene.store.send(.advance)
            scene.store.send(.startTraining)
            #expect(scene.store.state.phase == .saving)
            #expect(scene.store.attempt == OnboardingSaveAttempt(number: 1, goal: goal, days: days))
            await scene.save()

            let expected = try StoreScene.expectedProgram(goal: goal, days: days)
            #expect(scene.programs.saved == [expected])
            let active = try await scene.stores.programs.active()
            #expect(active == expected)
            #expect(scene.store.state.phase == .saved)
            #expect(scene.preparations == 0, "a first attempt prepares nothing")

            let saved = try #require(scene.programs.saved.first)
            #expect(saved.isActive)
            #expect(saved.goal == goal)
            #expect(saved.daysPerWeek == days.rawValue)
            #expect(saved.weeks.count == 8)
            #expect(saved.weeks.map(\.isDeload) == [false, false, false, false, false, false, false, true])
            #expect(saved.startDate == CivilDate(year: 2026, month: 9, day: 14), "Monday of the week of 2026-09-16")
            #expect(saved.name == ProgramTemplates.preview(days: days).programName)
        }
    }

    @Test(
        "Skip setup saves the default program, both on four days, whatever is picked and on any step",
        arguments: OnboardingState.Step.allCases
    )
    func skipSetup_savesTheDefault_whateverThePicks(on step: OnboardingState.Step) async throws {
        try await StoreScene.run { scene in
            scene.store.send(.pickGoal(.strength))
            for _ in 0 ..< step.rawValue {
                scene.store.send(.advance)
                scene.store.send(.pickDays(.six))
            }
            #expect(scene.store.state.step == step)
            scene.store.send(.skipSetup)
            #expect(scene.store.attempt == OnboardingSaveAttempt(number: 1, goal: .both, days: .four))
            await scene.save()

            let expected = try StoreScene.expectedProgram(goal: .both, days: .four)
            #expect(scene.programs.saved == [expected])
            #expect(scene.store.state.phase == .saved)
            #expect(scene.store.state.goal == .strength, "the picks themselves are left as they were")

            // What the fixture F09 and F10 build on calls "the program a skip saves", ids aside.
            let fixture = try Fixtures.defaultProgram()
            #expect(expected.name == fixture.name)
            #expect(expected.startDate == fixture.startDate)
            #expect(expected.days.map(\.name) == fixture.days.map(\.name))
            #expect(expected.days.flatMap(\.slots).map(\.startLoad) == fixture.days.flatMap(\.slots).map(\.startLoad))
        }
    }

    @Test("The block starts on the first day of the week as the stored settings count it")
    func save_usesTheSettingsWeekStart() async throws {
        var settings = Settings.default
        settings.weekStart = .sunday
        try await StoreScene.run(seed: .seeded(settings: settings)) { scene in
            await scene.startTraining()
            let sunday = CivilDate(year: 2026, month: 9, day: 13)
            #expect(scene.programs.saved.map(\.startDate) == [sunday])
            let expected = try StoreScene.expectedProgram(goal: .both, days: .four, startDate: sunday)
            #expect(scene.programs.saved == [expected])
        }
    }

    @Test("The week is the one that holds the injected date, in the injected calendar's time zone")
    func save_usesTheInjectedDateAndCalendar() async throws {
        // 03:00 UTC on Monday 2026-09-21 is still Sunday evening, the 20th, in Los Angeles.
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Fixtures.calendar
        calendar.timeZone = losAngeles
        let monday = Fixtures.date(2026, 9, 21, hour: 3)
        try await StoreScene.run(changes: [.date(monday), .calendar(calendar)]) { scene in
            await scene.startTraining()
            #expect(scene.programs.saved.map(\.startDate) == [CivilDate(year: 2026, month: 9, day: 14)])
        }
        try await StoreScene.run(changes: [.date(monday)]) { scene in
            await scene.startTraining()
            #expect(scene.programs.saved.map(\.startDate) == [CivilDate(year: 2026, month: 9, day: 21)])
        }
    }

    @Test("With kilograms stored, step 3 says kilograms and the saved loads are the catalog's kilogram loads")
    func kilograms_areShownAndSaved() async throws {
        try await StoreScene.run(seed: .seeded(settings: Fixtures.settingsKg)) { scene in
            #expect(scene.store.state.units == .lb, "the default's, until the settings are read")
            await scene.store.loadUnits()
            #expect(scene.store.state.units == .kg)
            await scene.startTraining()
            #expect(scene.store.model.body == "Upper / Lower, 8 weeks, kilograms. Editable any time.")

            let saved = try #require(scene.programs.saved.first)
            let expected = try StoreScene.expectedProgram(goal: .both, days: .four, units: .kg)
            #expect(saved == expected)
            let bench = try #require(StoreScene.catalog.first { $0.name == "Barbell Bench Press" })
            let benchSlot = try #require(saved.days.first?.slots.first)
            #expect(benchSlot.exerciseID == bench.id)
            #expect(benchSlot.startLoad == .kilograms(20))
            let byID = Dictionary(uniqueKeysWithValues: StoreScene.catalog.map { ($0.id, $0) })
            for slot in saved.days.flatMap(\.slots) {
                #expect(slot.startLoad == byID[slot.exerciseID]?.startLoad(in: .kg))
            }
        }
    }

    @Test("A save reads the unit itself: the sentence follows the settings even if they were never loaded")
    func save_readsTheUnitItSavesIn() async throws {
        try await StoreScene.run(seed: .seeded(settings: Fixtures.settingsKg)) { scene in
            await scene.startTraining()
            #expect(scene.store.state.units == .kg)
            let expected = try StoreScene.expectedProgram(goal: .both, days: .four, units: .kg)
            #expect(scene.programs.saved == [expected])
        }
    }
}
