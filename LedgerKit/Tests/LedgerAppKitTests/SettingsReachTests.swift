@testable import FeatureProgram
@testable import FeatureSettings
@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1, criteria 2 and 7 across the stores that read the settings: a change saved by Settings' store reaches the
/// Day editor's library, which gives a new slot the default rest, and Today's week strip, while the screens stay up,
/// over one set of in-memory stores (here, where every feature can be imported).
@MainActor
@Suite("Settings reach the other screens", .serialized, .timeLimit(.minutes(1)))
struct SettingsReachTests {
    /// The seed program, the catalog and the settings in pounds, behind every key the three stores read.
    struct Scene {
        let memory: InMemoryStores
        let program: Program
        let settings: SettingsStore
        let dayEditor: DayEditorStore
        let today: TodayStore

        init() throws {
            let seed = try Fixtures.seedProgram()
            var stores: InMemoryStores?
            let made = try withTestDependencies {
                stores = try $0.inMemoryStores(seed: InMemoryStores.Seed(
                    catalog: ExerciseCatalog.seed(),
                    programs: [seed],
                    settings: Fixtures.settingsLb
                ))
                $0.workoutSession = FakeWorkoutSessionClient()
                $0.uuid = .incrementing
            } operation: {
                (
                    SettingsStore(about: AppAbout(name: nil, version: nil, build: nil)),
                    DayEditorStore(day: seed.days[0].id, weekIndex: 4),
                    TodayStore()
                )
            }
            memory = try #require(stores)
            program = seed
            (settings, dayEditor, today) = made
        }

        /// Settings' run, once it shows its model.
        func runningSettings() async -> Task<Void, Never> {
            let task = Task { await settings.run() }
            await until { settings.model != nil }
            return task
        }

        /// Settings has saved every change, and the store gave it back.
        func settingsSaved() async {
            await until { settings.pending == nil }
        }
    }

    @Test("Criterion 2. A rest saved in Settings is what a new slot of the Day editor's library gets")
    func savedRest_reachesANewSlot() async throws {
        let scene = try Scene()
        let settings = await scene.runningSettings()
        let sources = Task { await scene.dayEditor.run() }
        let saving = Task { await scene.dayEditor.save() }
        defer {
            settings.cancel()
            sources.cancel()
            saving.cancel()
        }
        await until { scene.dayEditor.state != .loading }
        scene.settings.send(.setDefaultRest(RestDuration(clampingSeconds: 60)))
        await scene.settingsSaved()
        await until { scene.dayEditor.settings?.defaultRest.seconds == 60 }
        let squat = try await #require(scene.memory.exercises.all().first { $0.name == "Back Squat" }).id
        scene.dayEditor.send(.openLibrary)
        scene.dayEditor.send(ExercisePickerAction.setPicked(true, exercise: squat))
        scene.dayEditor.send(ExercisePickerAction.add([squat]))
        await until { scene.dayEditor.session.isIdle }
        let day = try #require(try await scene.memory.programs.active()?.days.first)
        #expect(day.slots.last?.exerciseID == squat)
        #expect(day.slots.last?.rest.seconds == 60)
    }

    @Test("Criterion 7. A week start saved in Settings redraws Today's strip from it; the program's weeks stay")
    func savedWeekStart_redrawsTodaysStrip() async throws {
        let scene = try Scene()
        let settings = await scene.runningSettings()
        let today = Task { await scene.today.run() }
        defer {
            settings.cancel()
            today.cancel()
        }
        await until { Self.strip(scene.today) != nil }
        // Wednesday 2026-09-16 (`Fixtures.now`): weeks from Monday start on the 14th.
        #expect(Self.strip(scene.today)?.first?.date == "14")
        scene.settings.send(.setWeekStart(.saturday))
        await scene.settingsSaved()
        await until { Self.strip(scene.today)?.first?.date == "12" }
        #expect(Self.strip(scene.today)?.count == 7)
        #expect(try await scene.memory.programs.active() == scene.program, "the block's weeks did not move")
    }

    /// Today's week strip, once it shows a model.
    private static func strip(_ store: TodayStore) -> [WeekStrip.Day]? {
        guard case let .loaded(model) = store.state else {
            return nil
        }
        return model.weekStrip
    }
}
