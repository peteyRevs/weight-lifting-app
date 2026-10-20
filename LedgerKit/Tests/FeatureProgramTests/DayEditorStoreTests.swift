@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// F11 S14, criteria 15 to 17: the Day editor's store over the in-memory stores behind a probe, run in tasks
/// as `DayEditorRoot`'s tasks run it. Each wait is on what the store shows (Observation), never on time.
@MainActor
@Suite("DayEditorStore", .tags(.feature), .timeLimit(.minutes(1)))
struct DayEditorStoreTests {
    // MARK: Criterion 15

    @Test("15. Loading until the sources have spoken; then the day in the route's week, with no panel open")
    func run_showsTheDayInTheRoutesWeek() async throws {
        let scene = try DayEditorStoreScene()
        #expect(scene.store.state == .loading)
        let running = await scene.running()
        let content = try scene.content
        #expect(content.header.name == "Upper A — Push focus")
        #expect(content.header.meta.hasPrefix("Week 5 · "))
        #expect(content.openRow == nil)
        await running.cancel()
    }

    @Test("15. A row opens and closes its panel; an edit that closes the panel closes it; nothing is written")
    func open_setsThePanel_andNothingIsWritten() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        try scene.store.send(scene.content.row("1").action)
        #expect(try scene.content.openRow?.index == "1")
        try scene.store.send(scene.content.row("2").action)
        #expect(try scene.content.openRow?.index == "2")
        try scene.store.send(scene.content.row("2").action)
        #expect(try scene.content.openRow == nil)
        try scene.store.send(scene.content.row("2").action)
        let remove = try #require(scene.content.openRow?.panel?.remove.action)
        let second = try scene.content.row("2").id
        #expect(remove == .edit(.slot(.remove(slot: second), day: scene.store.day), closesPanel: true))
        await scene.idle()
        #expect(await scene.writes() == 0, "opening a panel stores nothing")
        scene.store.send(remove)
        #expect(try scene.content.openRow == nil)
        await scene.idle()
        #expect(try await scene.storedDay()?.slots.count == 4)
        await running.cancel()
    }

    @Test("15. Two quick taps on a stepper's \"+\" are two steps: the second is taken from the model after the first")
    func stepper_twoQuickTaps_areTwoSteps() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        try scene.store.send(scene.content.row("1").action)
        let sets = try #require(scene.content.openRow?.panel?.details).field("SETS")
        scene.store.send(sets.increment)
        try await scene.probe.waitUntilHeld()
        try scene.store.send(#require(scene.content.openRow?.panel?.details).field("SETS").increment)
        #expect(try #require(scene.content.openRow?.panel?.details).value("SETS") == "7")
        await scene.probe.release()
        await scene.idle()
        #expect(try await scene.storedDay()?.slots.first?.sets == 7)
        #expect(await scene.writes() == 2)
        await running.cancel()
    }

    @Test("15. The drop-set switch and the name are applied before the intent returns")
    func dropSetAndName_areAppliedAtOnce() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        try scene.store.send(scene.content.row("1").action)
        let dropSet = try #require(scene.content.openRow?.panel?.details?.dropSet)
        #expect(!dropSet.isOn)
        scene.store.send(dropSet.action)
        #expect(try scene.content.openRow?.panel?.details?.dropSet.isOn == true)
        for count in 1 ... 7 {
            scene.store.send(.rename(String("Push day".prefix(count)), day: scene.store.day))
        }
        #expect(try scene.content.header.name == "Push da")
        await scene.idle()
        #expect(try await scene.storedDay()?.name == "Push da")
        #expect(try await scene.storedDay()?.slots.first?.dropSets == 1)
        await running.cancel()
    }

    @Test("15. A source that ended keeps the failed state through a new run until the program is heard again")
    func failedState_isKeptThroughANewRun() async throws {
        var counted: CountingPrograms?
        let gate = AsyncStream<Void>.makeStream()
        let scene = try DayEditorStoreScene { values, probed in
            let held = HeldSecondPrograms(base: probed.programs, gate: gate.stream)
            let counting = CountingPrograms(base: held)
            counted = counting
            values.programRepository = counting
        }
        let programs = try #require(counted)
        let first = await scene.running()
        #expect(scene.store.state == .failed)
        await first.cancel()
        let second = Task { await scene.store.run() }
        // The new run has asked for the program, which is held: it is running and has heard nothing yet.
        await programs.observed(2)
        #expect(scene.store.state == .failed, "not loading while the new run waits for its program")
        gate.continuation.yield()
        await eventually { scene.store.state != .failed }
        #expect(try scene.content.header.name == "Upper A — Push focus")
        second.cancel()
        await second.value
    }
}

/// A program store whose first observation ends at once and whose second says nothing until `gate` yields, then
/// follows the base: a new run that is running and has not yet heard its program.
final nonisolated class HeldSecondPrograms: ProgramRepository {
    let base: any ProgramRepository
    let gate: AsyncStream<Void>
    private let observations = Mutex(0)

    init(base: any ProgramRepository, gate: AsyncStream<Void>) {
        self.base = base
        self.gate = gate
    }

    func observeActive() -> AsyncStream<Program?> {
        let number = observations.withLock { count in
            count += 1
            return count
        }
        guard number > 1 else {
            return AsyncStream { $0.finish() }
        }
        let (source, opening) = (base, gate)
        return AsyncStream { continuation in
            let task = Task {
                for await _ in opening {
                    break
                }
                for await program in source.observeActive() {
                    continuation.yield(program)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
