@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: what the store emits while a write runs (criteria 2, 3 and 7, ruling R6): kept
/// aside and never drawn under the edits in flight; a workout's save made meanwhile is kept.
@MainActor
@Suite("Adversarial F11 S13 · emissions during a write", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramStoreEmissionsAdversarialTests {
    @Test("R6: \"−\" stored and emitted before its update returns is drawn once: seven weeks, never six")
    func removeLastWeek_emittedDuringTheWrite_isDrawnOnce() async throws {
        let rig = try S13SessionRig<ProgramBuilderEdit>(program: Fixtures.seedProgram())
        let follower = rig.follow()
        let loop = Task { await rig.session.run { _ in } }
        defer {
            loop.cancel()
            follower.cancel()
        }
        await rig.probe.hold(.updateProgram, afterStoring: true)
        #expect(rig.session.enqueue(.removeLastWeek(loggedWeeks: [])))
        try await rig.probe.waitUntilHeld()
        await s13Until { rig.session.heardDuringWrite != nil }
        #expect(rig.session.shown?.weeks.count == 7, "the emission is not drawn under the edit in flight")
        await rig.probe.release()
        await s13Until { rig.session.isIdle }
        #expect(rig.session.shown?.weeks.count == 7)
        #expect(try await rig.memory.programs.active()?.weeks.count == 7)
        // A later edit is applied to the seven, not to a stale eight or a doubled six.
        #expect(rig.session.enqueue(.setDeload(true, week: 6)))
        await s13Until { rig.session.isIdle }
        let stored = try #require(try await rig.memory.programs.active())
        #expect(stored.weeks.count == 7)
        #expect(stored.week(at: 6)?.isDeload == true)
        #expect(rig.session.shown == stored)
    }

    @Test("R6: a move stored and emitted before its update returns is drawn once (the Day editor's session)")
    func move_emittedDuringTheWrite_isDrawnOnce() async throws {
        var program = try ProgramFixtures.program(weekCount: 3, days: [ProgramFixtures.day(1, slotCount: 4)])
        program.isActive = true
        let slots = program.days[0].slots.map(\.id)
        let rig = try S13SessionRig<DayEditorEdit>(program: program)
        let follower = rig.follow()
        let loop = Task { await rig.session.run { _ in } }
        defer {
            loop.cancel()
            follower.cancel()
        }
        let day = program.days[0].id
        await rig.probe.hold(.updateProgram, afterStoring: true)
        #expect(rig.session.enqueue(.slot(.move(.upward, slot: slots[2]), day: day)))
        let once = [slots[0], slots[2], slots[1], slots[3]]
        #expect(rig.session.shown?.days[0].slots.map(\.id) == once)
        try await rig.probe.waitUntilHeld()
        await s13Until { rig.session.heardDuringWrite != nil }
        #expect(rig.session.shown?.days[0].slots.map(\.id) == once, "moved once, not twice")
        await rig.probe.release()
        await s13Until { rig.session.isIdle }
        #expect(rig.session.shown?.days[0].slots.map(\.id) == once)
        #expect(try await rig.memory.programs.active()?.days[0].slots.map(\.id) == once)
    }

    @Test("Criterion 2 and 7: a workout's misses saved while a rename waits at the store are kept, and both drawn")
    func workoutSavedDuringAWrite_bothAreKept() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("Waiting"))
        try await rig.probe.waitUntilHeld()
        try await Self.missTwoSets(rig)
        #expect(rig.session.shown?.name == "Waiting", "the edit stays on screen while its write is held")
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.name == "Waiting")
        #expect(stored.days[0].slots[0].misses == [0, 1], "the workout's save is kept")
        await s13Until { rig.session.shown == stored }
        #expect(rig.model?.header.name == "Waiting")
    }

    @Test("R6's gap: a workout saved after the write stored and before it returned is not lost from the screen")
    func workoutSavedAfterTheCommit_beforeTheReturn_isDrawn() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram, afterStoring: true)
        rig.store.send(.rename("Waiting"))
        try await rig.probe.waitUntilHeld()
        #expect(try await rig.storedProgram()?.name == "Waiting", "the rename is stored; its update has not returned")
        try await Self.missTwoSets(rig)
        // The store emits the rename and the misses together, newer than what the update will return.
        await s13Until { rig.session.heardDuringWrite??.days[0].slots[0].misses == [0, 1] }
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.days[0].slots[0].misses == [0, 1])
        // No emission follows: the store has nothing new to say. What the screen draws now, it draws until the
        // next change.
        #expect(rig.session.stored == stored, "the session holds a program older than the store's newest word")
        #expect(rig.session.shown == stored)
    }

    @Test("Behaviour 15: a program changed while edits wait (no write running yet) is drawn under them")
    func storedProgramChanges_whileIdle_isShownUnderTheEdits() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let id = try #require(rig.session.shown?.id)
        _ = try await rig.memory.programs.update(id) { ProgramEditing.renameProgram($0, to: "Elsewhere") }
        await s13Until { rig.model?.header.name == "Elsewhere" }
        // The name field's next keystroke wins (criterion 11, brief:581).
        rig.store.send(.rename("Mine"))
        await rig.settled()
        #expect(try await rig.storedProgram()?.name == "Mine")
    }

    /// A workout of week 5 saved with two sets of the first slot missed (rule 13's slot update).
    static func missTwoSets(_ rig: S13Rig) async throws {
        let program = try #require(try await rig.storedProgram())
        var missed = program.days[0].slots[0]
        missed.misses = [0, 1]
        _ = try await rig.memory.workouts.materialize(
            S13Fixtures.finished(week: 4, start: S13Fixtures.morning(week: 4)),
            slotUpdates: [missed],
            droppingLog: false
        )
    }
}
