import Dependencies
@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The four things a save does, each made to fail.
nonisolated enum FailingStep: String, CaseIterable, CustomTestStringConvertible {
    case settings, catalog, generator, write

    var testDescription: String {
        rawValue
    }

    /// The stores a first launch has, before the catalog is seeded when the generator is the one to fail.
    var seed: InMemoryStores.Seed {
        self == .generator ? .empty : .seeded()
    }

    var changes: [SceneChange] {
        switch self {
        case .settings: [.settingsCannotBeRead]
        case .catalog: [.catalogCannotBeRead]
        case .generator: []
        case .write: [.programCannotBeSaved]
        }
    }
}

/// F08 S2, criterion 7: a save that cannot finish shows the brief's sentence with "Retry", saves nothing, and
/// "Retry" awaits the root's preparation and then writes the program the failed attempt asked for.
@Suite("OnboardingStore: failure and retry", .tags(.feature), .timeLimit(.minutes(1)))
struct OnboardingStoreFailureTests {
    @Test(
        "Whichever step fails, the screen shows the sentence with Retry and nothing is saved",
        arguments: FailingStep.allCases
    )
    func save_failure_showsRetry_andSavesNothing(_ step: FailingStep) async throws {
        try await StoreScene.run(seed: step.seed, changes: step.changes) { scene in
            scene.store.send(.pickGoal(.strength))
            await scene.startTraining()

            #expect(scene.store.state.phase == .failed)
            #expect(scene.programs.saved.isEmpty)
            let active = try await scene.stores.programs.active()
            #expect(active == nil)
            let model = scene.store.model
            #expect(model.error == "Couldn't save your program. Try again.")
            #expect(model.primary == .init(title: "Retry", action: .retry))
            #expect(model.canProceed && !model.canEdit)
            #expect(scene.store.state.step == .program, "the step is where the lifter was")
            #expect(scene.store.state.goal == .strength, "and so are the picks")
            #expect(scene.preparations == 0, "a first attempt prepares nothing")
        }
    }

    @Test("An unseeded catalog fails the save as the generator's unknown exercise, before anything is written")
    func save_unseededCatalog_showsRetry_andSavesNothing() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            scene.store.send(.skipSetup)
            await scene.save()
            #expect(scene.store.state.phase == .failed)
            #expect(scene.programs.saved.isEmpty)
            let monday = try #require(CivilDate(year: 2026, month: 9, day: 14))
            #expect(throws: ProgramTemplateError.unknownExercise("Barbell Bench Press")) {
                try ProgramTemplates.program(
                    ProgramTemplates.Request(goal: .both, days: .four, units: .lb, startDate: monday),
                    catalog: [],
                    id: ProgramID(UUID(0)),
                    newID: { UUID(1) }
                )
            }
        }
    }

    @Test("A date whose week no calendar date can name fails the save; it is not unwrapped")
    func save_startDateOutOfRange_showsRetry() async throws {
        let year12000 = Date(timeIntervalSince1970: 316_500_000_000)
        try await StoreScene.run(changes: [.date(year12000)]) { scene in
            let calendar = Fixtures.calendar
            let start = ProgramTemplates.startDate(containing: year12000, weekStart: .monday, calendar: calendar)
            #expect(start == nil, "the generator's own answer for this date")
            await scene.startTraining()
            #expect(scene.store.state.phase == .failed)
            #expect(scene.programs.saved.isEmpty)
        }
    }

    @Test("Retry prepares first, then saves the program the failed attempt asked for")
    func retry_onceTheCatalogIsSeeded_savesTheSamePicks() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            scene.store.send(.pickGoal(.strength))
            scene.store.send(.advance)
            scene.store.send(.pickDays(.six))
            scene.store.send(.advance)
            scene.store.send(.startTraining)
            await scene.save { Issue.record("a first attempt must not prepare") }
            #expect(scene.store.state.phase == .failed)

            scene.store.send(.retry)
            #expect(scene.store.state.phase == .retrying)
            #expect(scene.store.attempt == OnboardingSaveAttempt(number: 2, goal: .strength, days: .six))
            #expect(scene.store.model.error == nil, "the sentence goes while the retry runs")
            #expect(scene.store.model.primary.title == "Retry")
            // The retry can only succeed if the preparation, which seeds the catalog, was awaited before the read.
            await scene.save { try? await scene.seedCatalog() }

            #expect(scene.preparations == 1)
            #expect(scene.store.state.phase == .saved)
            // The failed attempt drew the program's id (0) and no other, so the retry's ids start at 1.
            let expected = try StoreScene.expectedProgram(goal: .strength, days: .six, firstID: 1)
            #expect(scene.programs.saved == [expected])
            let active = try await scene.stores.programs.active()
            #expect(active == expected)
        }
    }

    @Test("A retry that fails again shows the sentence again, saves nothing, and can be retried")
    func retry_failingAgain_staysFailed() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            await scene.startTraining()
            scene.store.send(.retry)
            await scene.save()
            #expect(scene.preparations == 1)
            #expect(scene.store.state.phase == .failed)
            #expect(scene.store.model.error == "Couldn't save your program. Try again.")
            #expect(scene.programs.saved.isEmpty)

            scene.store.send(.retry)
            #expect(scene.store.attempt?.number == 3)
            await scene.save { try? await scene.seedCatalog() }
            #expect(scene.preparations == 2)
            #expect(scene.programs.saved.count == 1)
            #expect(scene.store.state.phase == .saved)
        }
    }

    @Test("Retry after a failed Skip setup saves the default again, not the picks")
    func retry_afterAFailedSkip_savesTheDefault() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            scene.store.send(.pickGoal(.strength))
            scene.store.send(.skipSetup)
            await scene.save()
            #expect(scene.store.state.phase == .failed)
            #expect(scene.store.state.step == .goal, "the failure is shown on the step the lifter skipped from")

            scene.store.send(.retry)
            await scene.save { try? await scene.seedCatalog() }
            let expected = try StoreScene.expectedProgram(goal: .both, days: .four, firstID: 1)
            #expect(scene.programs.saved == [expected])
        }
    }

    @Test("Skip setup after a failure is a retry too: it prepares first, and saves the default")
    func skipSetup_afterAFailure_preparesFirst() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            scene.store.send(.pickGoal(.strength))
            await scene.startTraining()
            scene.store.send(.skipSetup)
            #expect(scene.store.state.phase == .retrying)
            await scene.save { try? await scene.seedCatalog() }
            #expect(scene.preparations == 1)
            let expected = try StoreScene.expectedProgram(goal: .both, days: .four, firstID: 1)
            #expect(scene.programs.saved == [expected])
        }
    }

    @Test("While a failed attempt waits for its retry, the picks and the step are locked")
    func failed_locksThePicksAndTheStep() async throws {
        try await StoreScene.run(seed: .empty) { scene in
            await scene.startTraining()
            let failed = scene.store.state
            let attempt = scene.store.attempt
            for action in [OnboardingAction.pickGoal(.strength), .pickDays(.six), .back, .advance, .startTraining] {
                scene.store.send(action)
                #expect(scene.store.state == failed, "\(action)")
                #expect(scene.store.attempt == attempt, "\(action)")
            }
        }
    }

    @Test("Retry does nothing unless the last attempt failed")
    func retry_whileEditing_doesNothing() async throws {
        try await StoreScene.run { scene in
            scene.store.send(.retry)
            #expect(scene.store.state == OnboardingState())
            #expect(scene.store.attempt == nil)
            await scene.save()
            #expect(scene.programs.saved.isEmpty)
        }
    }
}
