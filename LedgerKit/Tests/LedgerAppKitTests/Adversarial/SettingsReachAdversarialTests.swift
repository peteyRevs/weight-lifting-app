@testable import FeatureProgram
@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S1a, G2: the cross-store criteria from the other side, and the store over the real GRDB repository.
/// Criterion 2 says a saved rest is what a NEW slot gets: the slots already in the program keep theirs. The store's
/// saves over GRDB's `.task`-scheduled observation (whose echoes come after `write` returns) end on the lifter's
/// last value, with nothing left pending; on the way, the screen sometimes leaves it (F14-S1-3, intermittent).
/// A seeded burst of changes: a week start, the units or Plate math, each sent to the store and kept in `lifter`.
@MainActor
struct SettingsBurst {
    var state: UInt64

    mutating func roll(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    mutating func change(_ store: SettingsStore, _ lifter: inout Settings) {
        let day = Weekday.allCases[roll(7)]
        let isOn = roll(2) == 0
        switch roll(3) {
        case 0:
            store.send(.setWeekStart(day))
            lifter.weekStart = day
        case 1:
            store.send(.setUnits(isOn ? .kg : .lb))
            lifter.units = isOn ? .kg : .lb
        default:
            store.send(.setPlateMath(isOn))
            lifter.plateMathEnabled = isOn
        }
    }
}

@MainActor
@Suite("Settings reach, adversarial", .serialized, .timeLimit(.minutes(1)))
struct SettingsReachAdversarialTests {
    @Test("Criterion 2. A saved rest leaves every slot already in the program as it was")
    func savedRest_leavesExistingSlots() async throws {
        let scene = try SettingsReachTests.Scene()
        let settings = await scene.runningSettings()
        let sources = Task { await scene.dayEditor.run() }
        let saving = Task { await scene.dayEditor.save() }
        defer {
            settings.cancel()
            sources.cancel()
            saving.cancel()
        }
        await until { scene.dayEditor.state != .loading }
        let before = try #require(try await scene.memory.programs.active()).days.flatMap(\.slots).map(\.rest.seconds)
        #expect(!before.contains(45), "the fixture has no 45 s rest, so a leak would show")
        scene.settings.send(.setDefaultRest(RestDuration(clampingSeconds: 45)))
        await scene.settingsSaved()
        await until { scene.dayEditor.settings?.defaultRest.seconds == 45 }
        let squat = try await #require(scene.memory.exercises.all().first { $0.name == "Back Squat" }).id
        scene.dayEditor.send(.openLibrary)
        scene.dayEditor.send(ExercisePickerAction.setPicked(true, exercise: squat))
        scene.dayEditor.send(ExercisePickerAction.add([squat]))
        await until { scene.dayEditor.session.isIdle }
        let program = try #require(try await scene.memory.programs.active())
        let firstDay = try #require(program.days.first)
        #expect(firstDay.slots.last?.rest.seconds == 45, "the new slot")
        let others = program.days.enumerated().flatMap { index, day in
            index == 0 ? Array(day.slots.dropLast()) : day.slots
        }.map(\.rest.seconds)
        #expect(others == before, "every slot already there kept its rest")
    }

    @Test("R7 over GRDB. Bursts of changes end with the row, the screen and the lifter agreeing", arguments: 0 ..< 6)
    func grdb_burstsConverge(seed: Int) async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue)
        try await repository.save(Fixtures.settingsLb)
        let store = withTestDependencies {
            $0.settingsRepository = repository
        } operation: {
            SettingsStore(about: AppAbout(name: nil, version: nil, build: nil))
        }
        let task = Task { await store.run() }
        defer { task.cancel() }
        await until { store.model != nil }
        var lifter = Fixtures.settingsLb
        var flickers = 0
        var generator = SettingsBurst(state: UInt64(seed) &* 2_654_435_761 &+ 7)
        for _ in 0 ..< 60 {
            generator.change(store, &lifter)
            for _ in 0 ..< generator.roll(40) {
                await Task.yield()
            }
            if store.shown != lifter {
                flickers += 1
            }
        }
        #expect(flickers == 0, "seed \(seed): the screen left the lifter's value \(flickers) times")
        await until { store.pending == nil }
        let row = try await repository.load()
        let rowIsLifters = row == lifter
        let shownIsLifters = store.shown == lifter
        #expect(rowIsLifters, "seed \(seed): the row is not the lifter's last value")
        #expect(shownIsLifters, "seed \(seed): the screen is not the lifter's last value")
    }
}
