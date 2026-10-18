import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13, criteria 1 to 6: the edit session, driven through the builder's store on the in-memory stores
/// behind a probe (and on the database for criterion 2), with no clock and no sleep: a write is held by the
/// probe where a test needs it to be in flight.
@MainActor
@Suite("ProgramEditSession", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramEditSessionTests {
    // MARK: Criterion 1

    @Test("1. The first edit is written at once; the edits made while it is written go together in the next write")
    func edit_isSavedAtOnce_andEditsMadeMeanwhileGoTogether() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.edit(.setDeload(true, week: 0)))
        try await scene.probe.waitUntilHeld()
        scene.store.send(.edit(.setDeload(true, week: 1)))
        scene.store.send(.edit(.setDeload(true, week: 2)))
        scene.store.send(.rename("Block A"))
        #expect(scene.store.session.waiting.count == 4)
        #expect(try scene.model.header.name == "Block A", "every edit is on screen before it is stored")
        await scene.probe.release()
        await scene.idle()
        #expect(await scene.writes() == 2)
        let stored = try await scene.stored()
        #expect(stored == scene.store.session.shown, "the stored program is the one on screen")
        #expect(stored.weeks.prefix(3).allSatisfy(\.isDeload) && stored.name == "Block A")
        await running.cancel()
    }

    // MARK: Criterion 2

    @Test("2. A workout saved while an edit waits keeps its miss and its swap, and the edit is kept, in memory")
    func workoutSavedDuringAnEdit_bothAreKept_inMemory() async throws {
        let scene = try ProgramStoreScene()
        try await Self.losingSequence(store: scene.store, probe: scene.probe, workouts: scene.memory.workouts)
        #expect(await scene.writes() == 1)
    }

    @Test("2. A workout saved while an edit waits keeps its miss and its swap, and the edit is kept, on the database")
    func workoutSavedDuringAnEdit_bothAreKept_onTheDatabase() async throws {
        let database = try await ProgramDatabase()
        let probed = ProbedStores(events: database.events, workouts: database.workouts, programs: database.programs)
        let store = withTestDependencies {
            $0.exerciseRepository = database.exercises
            $0.programRepository = probed.programs
            $0.workoutRepository = database.workouts
            $0.settingsRepository = database.settings
        } operation: {
            ProgramStore()
        }
        try await Self.losingSequence(store: store, probe: probed.probe, workouts: database.workouts)
    }

    /// S3's losing sequence through the store: the builder has read the program; while its edit waits to be
    /// written, a finished workout's save writes a miss and a swap into Upper A's first slot; the edit is
    /// written. Both must be in the stored program.
    static func losingSequence(store: ProgramStore, probe: StoreProbe, workouts: any WorkoutRepository) async throws {
        let sources = Task { await store.run() }
        let saving = Task { await store.save() }
        await eventually { store.state.isLoaded }
        let read = try #require(store.session.stored)
        await probe.hold(.updateProgram)
        store.send(.edit(.setDeload(true, week: 1)))
        try await probe.waitUntilHeld()
        let slot = read.days[0].slots[0]
        var workout = try finishedWorkout(of: read, weekIndex: 4)
        workout.programUpdates = [slot.id: Fixtures.CatalogID.inclineDBPress]
        var missed = slot
        missed.misses = [3]
        _ = try await workouts.materialize(workout, slotUpdates: [missed], droppingLog: false)
        await probe.release()
        await eventually { store.session.isIdle }
        let stored = try #require(store.session.stored)
        #expect(stored.days[0].slots[0].exerciseID == Fixtures.CatalogID.inclineDBPress, "the swap is kept")
        #expect(stored.days[0].slots[0].misses == [3], "the miss is kept")
        #expect(stored.weeks[1].isDeload, "the edit is kept")
        sources.cancel()
        saving.cancel()
    }

    // MARK: Criterion 3

    @Test("3. The program emitted before the update returns is not drawn under the removal in flight: one week goes")
    func emissionDuringAWrite_isNotDrawnUnderTheEdit_removeLastWeek() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram, afterStoring: true)
        try scene.store.send(scene.model.block.removeWeek)
        try await scene.probe.waitUntilHeld()
        #expect(try await scene.stored().weeks.count == 7, "stored, and emitted, but not returned yet")
        await eventually { scene.store.session.heardDuringWrite != nil }
        #expect(try scene.model.block.chips.count == 7, "the emission, which holds the removal, is kept aside")
        await scene.probe.release()
        await scene.idle()
        #expect(try scene.model.block.chips.count == 7)
        #expect(scene.store.session.heardDuringWrite == nil)
        #expect(try await scene.stored().weeks.count == 7)
        await running.cancel()
    }

    @Test("3. The program emitted before the update returns is not drawn under the move in flight: it moves once")
    func emissionDuringAWrite_isNotDrawnUnderTheEdit_move() async throws {
        let program = try Fixtures.seedProgram()
        let memory = try InMemoryStores(seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [program]))
        let probed = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
        let session = withTestDependencies { $0.programRepository = probed.programs } operation: {
            ProgramEditSession<DayEditorEdit>()
        }
        let hearing = Task {
            for await stored in memory.programs.observeActive() {
                session.hear(stored)
            }
        }
        let writing = Task { await session.run { _ in } }
        await eventually { session.hasHeard }
        let day = program.days[0]
        await probed.probe.hold(.updateProgram, afterStoring: true)
        session.enqueue(.slot(.move(.downward, slot: day.slots[0].id), day: day.id))
        try await probed.probe.waitUntilHeld()
        await eventually { session.heardDuringWrite != nil }
        let moved = program.days[0].slots.map(\.id).swappedFirstTwo
        #expect(session.shown?.days[0].slots.map(\.id) == moved, "moved once, not twice")
        await probed.probe.release()
        await eventually { session.isIdle }
        #expect(session.shown?.days[0].slots.map(\.id) == moved)
        #expect(try await memory.programs.active()?.days[0].slots.map(\.id) == moved)
        hearing.cancel()
        writing.cancel()
    }

    // MARK: Criterion 4

    @Test("4. An edit that changes nothing is not queued: a deload set to what it is, the stored name, a blank name")
    func editThatChangesNothing_isNotWritten() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let name = try scene.model.header.name
        scene.store.send(.edit(.setDeload(false, week: 0)))
        scene.store.send(.rename(name))
        scene.store.send(.rename("   "))
        scene.store.send(.edit(.setSchedule(week: 0, weekday: .tuesday, day: nil)))
        #expect(scene.store.session.waiting.isEmpty)
        scene.store.send(.edit(.setDeload(true, week: 0)))
        await scene.idle()
        #expect(await scene.writes() == 1, "only the last edit was written")
        await running.cancel()
    }

    // MARK: Criterion 5

    @Test("5. A write that fails drops every waiting edit, shows the stored program and says so; the next is stored")
    func saveFails_showsTheStoredProgramAndSaysSo() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let before = try await scene.stored()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.edit(.setDeload(true, week: 1)))
        try await scene.probe.waitUntilHeld()
        scene.store.send(.edit(.setDeload(true, week: 2)))
        await scene.probe.fail(.updateProgram)
        await scene.probe.release()
        await scene.idle()
        #expect(await scene.writes() == 1, "the edit that was waiting is not sent")
        #expect(try await scene.stored() == before)
        #expect(scene.store.session.shown == before)
        #expect(try scene.model.notice == "That change wasn't saved. Try again.")
        #expect(try !scene.model.block.chips[1].isDeload && !scene.model.block.chips[2].isDeload)

        scene.store.send(.edit(.setDeload(true, week: 3)))
        await scene.idle()
        #expect(try scene.model.notice == nil, "the next edit drops the line")
        #expect(try await scene.stored().weeks[3].isDeload)
        #expect(try await !scene.stored().weeks[1].isDeload)
        await running.cancel()
    }
}

private extension Array {
    /// The array with its first two elements in each other's place.
    var swappedFirstTwo: [Element] {
        var swapped = self
        swapped.swapAt(0, 1)
        return swapped
    }
}
