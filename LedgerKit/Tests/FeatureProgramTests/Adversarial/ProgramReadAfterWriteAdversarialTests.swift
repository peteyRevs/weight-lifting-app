@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 2: the read of the stored program after a write during which an emission was heard
/// (fix round 1 for F11-S13-1, R6 amended). The read is attacked where it can go wrong: an emission arriving
/// while it runs, a read that fails, a read that names another program or none, and a storm with workouts saved
/// between the taps. After every one the screen must end on what the store holds.
@MainActor
@Suite("Adversarial F11 S13 · the read after a heard write", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramReadAfterWriteAdversarialTests {
    /// Holds a rename's `update` once it has stored, until the session has heard the store's emission of it.
    static func renameHeardDuringItsWrite(_ rig: S13Rig) async throws {
        await rig.probe.hold(.updateProgram, afterStoring: true)
        rig.store.send(.rename("Waiting"))
        try await rig.probe.waitUntilHeld()
        await s13Until { rig.session.heardDuringWrite != nil }
    }

    /// A second program, sharing no id with the seed, stored and not active.
    static func otherProgram() throws -> Program {
        try Program(
            id: ProgramID(Fixtures.uuid(77777)),
            name: "Other block",
            startDate: #require(CivilDate(year: 2026, month: 9, day: 7)),
            weeks: (0 ..< 3).map { Week(id: WeekID(Fixtures.uuid(77800 + $0)), index: $0) },
            days: [DayTemplate(id: DayTemplateID(Fixtures.uuid(77900)), name: "Full body", tag: "FB")]
        )
    }

    @Test("A workout saved while the session reads the store after its write is not lost from the screen")
    func emissionDuringTheRead_isDrawn() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        // The read after the write is held once it has read: the misses come after it, and are emitted.
        await rig.probe.hold(.activeProgram, afterStoring: true)
        await rig.probe.release()
        try await rig.probe.waitUntilHeld()
        try await ProgramStoreEmissionsAdversarialTests.missTwoSets(rig)
        await s13Until { rig.session.heardDuringWrite??.days[0].slots[0].misses == [0, 1] }
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.name == "Waiting")
        #expect(stored.days[0].slots[0].misses == [0, 1])
        #expect(rig.session.stored == stored, "the session holds the read, older than the store's newest word")
        #expect(rig.session.shown == stored)
    }

    @Test("Amended R6: a read that fails leaves the returned program, which holds the write; nothing waits")
    func readFails_keepsTheReturnedProgram() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        await rig.probe.fail(.activeProgram)
        await rig.probe.release()
        await rig.settled()
        #expect(rig.session.shown?.name == "Waiting")
        #expect(rig.session.waiting.isEmpty)
        #expect(rig.store.notice == nil, "the write stored; a failed read is not a failed write")
        // The next edit is written over what the store holds and drawn from it.
        await rig.probe.heal()
        rig.store.send(.edit(.setDeload(true, week: 1)))
        await rig.settled()
        #expect(try await rig.session.shown == (rig.storedProgram()))
    }

    @Test("Another program made active during the write: the screen follows it, not the one just written")
    func readNamesAnotherProgram_isFollowed() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let other = try Self.otherProgram()
        try await rig.memory.programs.save(other)
        try await Self.renameHeardDuringItsWrite(rig)
        try await rig.memory.programs.setActive(other.id)
        await s13Until { rig.session.heardDuringWrite??.id == other.id }
        await rig.probe.release()
        await rig.settled()
        #expect(try await rig.storedProgram()?.id == other.id)
        #expect(rig.session.stored?.id == other.id, "the builder still shows \(rig.session.stored?.name ?? "none")")
        #expect(rig.model?.header.name == "Other block")
    }

    @Test("The active program deleted during the write: the builder shows the empty state, not the deleted one")
    func readNamesNoProgram_isTheEmptyState() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        let id = try #require(rig.session.stored?.id)
        try await rig.memory.programs.delete(id)
        await s13Until { rig.session.heardDuringWrite == .some(nil) }
        await rig.probe.release()
        await rig.settled()
        #expect(try await rig.storedProgram() == nil)
        #expect(rig.store.state == .noProgram, "the builder shows \(rig.model?.header.name ?? "no model")")
    }

    @Test(
        "A storm of taps with workouts saved between them and writes held at random: the screen ends on the store",
        arguments: PropertySeed.all
    )
    func stormWithWorkoutsSaved_endsOnTheStore(seed: PropertySeed) async throws {
        var random = seed.generator
        let rig = try S13Rig(yields: Int.random(in: 0 ... 2, using: &random))
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        for tap in 0 ..< 30 {
            if Int.random(in: 0 ..< 3, using: &random) == 0 {
                await rig.probe.hold(.updateProgram, afterStoring: Bool.random(using: &random))
            }
            let model = try #require(rig.model, "\(seed): no model")
            rig.store.send(ProgramSaveLoopAdversarialTests.pick(
                ProgramSaveLoopAdversarialTests.offered(model),
                &random
            ))
            if Int.random(in: 0 ..< 4, using: &random) == 0 {
                try await Self.saveAWorkout(rig, tap: tap)
            }
            if Int.random(in: 0 ..< 3, using: &random) == 0 {
                await rig.probe.release()
            }
            for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
                await Task.yield()
            }
        }
        while !rig.session.isIdle {
            await rig.probe.release()
            await Task.yield()
        }
        let stored = try #require(try await rig.storedProgram())
        // Let the follower hand on whatever the store emitted last (no clock: the main actor given way).
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(rig.session.stored == stored, "\(seed)")
        #expect(rig.session.shown == stored, "\(seed)")
        #expect(rig.store.notice != .saveFailed, "\(seed)")
    }

    /// A workout of week 5 saved with set `tap % 3` of the first slot missed.
    static func saveAWorkout(_ rig: S13Rig, tap: Int) async throws {
        guard let stored = try await rig.storedProgram() else {
            return
        }
        var missed = stored.days[0].slots[0]
        missed.misses = [tap % 3]
        _ = try await rig.memory.workouts.materialize(
            S13Fixtures.finished(week: 4, start: S13Fixtures.morning(week: 4), number: 100 + tap),
            slotUpdates: [missed],
            droppingLog: false
        )
    }
}
