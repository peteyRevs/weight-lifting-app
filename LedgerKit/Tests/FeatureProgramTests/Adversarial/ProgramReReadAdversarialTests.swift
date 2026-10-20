@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// F11 S13 adversarial round 3: the re-read loop of fix round 2 (`newestAfter`: read while the read itself
/// hears an emission) and the per-run ended flag (review SF1). A program store that writes, and so emits, while
/// each of the session's reads runs; one that throws on a later read; one that names nothing and then another
/// program; an observation that ends in one run, not in the next, and again in the third.
@MainActor
@Suite("Adversarial F11 S13 · the re-read after a heard write", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramReReadAdversarialTests {
    /// Holds a rename's `update` once it has stored, until the session has heard the store's emission of it.
    static func renameHeardDuringItsWrite(_ rig: S13Rig) async throws {
        await rig.probe.hold(.updateProgram, afterStoring: true)
        rig.store.send(.rename("Waiting"))
        try await rig.probe.waitUntilHeld()
        await s13Until { rig.session.heardDuringWrite != nil }
    }

    /// Writes misses to the first slot of the active program directly, as a workout's save does, and gives the
    /// main actor way so the store's follower hears the emission while the session's read is still running.
    static func writeMisses(_ memory: InMemoryStores, _ misses: Set<Int>) async throws {
        guard let program = try await memory.programs.active() else {
            return
        }
        _ = try await memory.programs.update(program.id) { stored in
            var changed = stored
            changed.days[0].slots[0].misses = misses
            return changed
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    @Test("An emission during every read: the reading stops at its bound on the last read; the next edit heals it")
    func emissionDuringEveryRead_stopsAtTheBound() async throws {
        // Sanctioned edit (S14, G3 round-2 note 2, F11-S13-11): the loop is bounded. Before S14 it read until
        // the store went quiet, twenty-one reads for twenty emissions.
        let bound = ProgramEditSession<ProgramBuilderEdit>.readsAfterAWrite
        let hook = S13ReadHook()
        let rig = try S13Rig { S13HookedPrograms(base: $0, hook: hook) }
        let memory = rig.memory
        hook.set { read in
            if read <= bound {
                try await Self.writeMisses(memory, [read % 3])
            }
        }
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        await rig.probe.release()
        await rig.settled()
        #expect(hook.reads == bound, "one read per emission heard, up to the bound")
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.name == "Waiting")
        #expect(rig.session.shown?.name == "Waiting", "the last read holds the write")
        let isBehind = rig.session.shown?.days[0].slots[0].misses != stored.days[0].slots[0].misses
        #expect(isBehind, "what was heard during the last read is not drawn")
        rig.store.send(.edit(.setDeload(true, week: 1)))
        await rig.settled()
        let healed = try #require(try await rig.storedProgram())
        #expect(healed.week(at: 1)?.isDeload == true)
        #expect(rig.session.shown == healed)
    }

    @Test("A read that throws on the second turn keeps the first read, which holds the write; the next edit heals it")
    func readThrowsOnTheSecondTurn_keepsTheNewest() async throws {
        let hook = S13ReadHook()
        let rig = try S13Rig { S13HookedPrograms(base: $0, hook: hook) }
        let memory = rig.memory
        hook.set { read in
            switch read {
            case 1: try await Self.writeMisses(memory, [1])
            case 2: throw S13Refused()
            default: break
            }
        }
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        // Saved after the write committed: the first read finds it, newer than what `update` returns.
        try await ProgramStoreEmissionsAdversarialTests.missTwoSets(rig)
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.days[0].slots[0].misses == [1])
        // Sanctioned edit (S14, F11-S13-10): a read that throws keeps the last read that answered, the first
        // ([0, 1]), not the older program `update` returned (no misses); the store holds [1]. The next edit
        // heals it.
        #expect(rig.session.stored?.name == "Waiting", "the write is shown")
        #expect(rig.session.stored?.days[0].slots[0].misses == [0, 1], "the last read that answered")
        rig.store.send(.edit(.setDeload(true, week: 1)))
        await rig.settled()
        #expect(try await rig.session.shown == (rig.storedProgram()))
        #expect(rig.store.notice == nil)
    }

    @Test("Nothing active on the first read, another program on the second: the builder follows the second")
    func nilThenAProgram_followsTheProgram() async throws {
        let other = try ProgramReadAfterWriteAdversarialTests.otherProgram()
        let hook = S13ReadHook()
        let rig = try S13Rig { S13HookedPrograms(base: $0, hook: hook) }
        let memory = rig.memory
        hook.set { read in
            if read == 1 {
                try await memory.programs.setActive(other.id)
                for _ in 0 ..< 20 {
                    await Task.yield()
                }
            }
        }
        try await memory.programs.save(other)
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        try await Self.renameHeardDuringItsWrite(rig)
        let id = try #require(rig.session.stored?.id)
        try await memory.programs.delete(id)
        await s13Until { rig.session.heardDuringWrite == .some(nil) }
        await rig.probe.release()
        await rig.settled()
        #expect(hook.reads == 2)
        #expect(rig.session.stored?.id == other.id)
        #expect(rig.model?.header.name == "Other block")
    }

    @Test("SF1: an observation ends in the first run, not in the second, and again in the third: failed, shown, failed")
    func endedFlag_isPerRun() async throws {
        let rig = try S13Rig { S13PatternPrograms(base: $0, endings: [true, false, true]) }
        let first = await rig.start()
        #expect(rig.store.state == .failed)
        first.sources.cancel()
        await first.sources.value
        let second = Task { await rig.store.run() }
        await s13Until { rig.model != nil }
        second.cancel()
        await second.value
        #expect(rig.model != nil, "a run cancelled is not a run that failed")
        let third = Task { await rig.store.run() }
        await s13Until { rig.store.state == .failed }
        third.cancel()
        await third.value
        first.saves.cancel()
    }
}

/// What a hooked program store runs after each read of the active program, with the read's number from 1.
final nonisolated class S13ReadHook: Sendable {
    private let body = Mutex<(@Sendable (Int) async throws -> Void)?>(nil)
    private let count = Mutex(0)

    func set(_ hook: @escaping @Sendable (Int) async throws -> Void) {
        body.withLock { $0 = hook }
    }

    var reads: Int {
        count.withLock { $0 }
    }

    func afterRead() async throws {
        let read = count.withLock { count in
            count += 1
            return count
        }
        let hook = body.withLock { $0 }
        try await hook?(read)
    }
}

/// A program store that reads, then runs its hook before it answers.
nonisolated struct S13HookedPrograms: ProgramRepository {
    let base: any ProgramRepository
    let hook: S13ReadHook

    func active() async throws -> Program? {
        let read = try await base.active()
        try await hook.afterRead()
        return read
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        try await base.update(id, change)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}

/// A program store whose observations end or not by `endings`, in order; later ones are the base's.
final nonisolated class S13PatternPrograms: ProgramRepository, Sendable {
    let base: any ProgramRepository
    private let endings: Mutex<[Bool]>

    init(base: any ProgramRepository, endings: [Bool]) {
        self.base = base
        self.endings = Mutex(endings)
    }

    func observeActive() -> AsyncStream<Program?> {
        let ends = endings.withLock { $0.isEmpty ? false : $0.removeFirst() }
        return ends ? AsyncStream { $0.finish() } : base.observeActive()
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        try await base.update(id, change)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }
}
