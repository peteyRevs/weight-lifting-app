@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// F11 S13 adversarial round 1: the Day editor's route after "+ Add training day" (criterion 13) and the store's
/// sources (criterion 7).
@MainActor
@Suite("Adversarial F11 S13 · routes and sources", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramStoreRoutesAdversarialTests {
    @Test("Criterion 13: the Day editor's route waits behind a write running when the day was added, then its own")
    func addDay_behindAnotherWrite_routeOnlyAfterItsOwnWrite() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("Before the day"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.addDay(name: "Day 5", weekIndex: 4))
        // The first write returns; the second, which holds the day, is held in its turn.
        await rig.probe.hold(.updateProgram)
        await rig.probe.release()
        try await rig.probe.waitUntilHeld()
        #expect(try await rig.storedProgram()?.days.count == 4, "the day is not stored yet")
        #expect(rig.store.pendingRoute == nil, "no route while the day's write runs")
        await rig.probe.release()
        await rig.settled()
        let day = DayTemplateID(S13IDs.id(0))
        #expect(try await rig.storedProgram()?.days.map(\.id).contains(day) == true)
        await s13Until { rig.store.pendingRoute != nil }
        #expect(rig.store.pendingRoute?.route == .day(day, weekIndex: 4))
    }

    @Test("Criterion 13: a double tap on \"+ Add training day\" while its route waits adds one day")
    func addDay_doubleTap_addsOneDay() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.addDay(name: "Day 5", weekIndex: 0))
        rig.store.send(.addDay(name: "Day 5", weekIndex: 0))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.addDay(name: "Day 5", weekIndex: 0))
        await rig.probe.release()
        await rig.settled()
        #expect(try await rig.storedProgram()?.days.count == 5)
        #expect(rig.session.shown?.days.count == 5)
        var handed: [ProgramRoute] = []
        rig.store.deliverRoute { handed.append($0) }
        rig.store.deliverRoute { handed.append($0) }
        #expect(handed == [.day(DayTemplateID(S13IDs.id(0)), weekIndex: 0)])
    }

    @Test("Criterion 13: a failed write emits no route, and the next \"+ Add training day\" is not held back")
    func addDay_failedWrite_noRoute_andTheNextTapWorks() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.fail(.updateProgram)
        rig.store.send(.addDay(name: "Day 5", weekIndex: 0))
        await rig.settled()
        #expect(rig.store.notice == .saveFailed)
        #expect(rig.store.pendingRoute == nil)
        #expect(rig.store.routeAfterSave == nil)
        rig.store.send(.addDay(name: "Day 5", weekIndex: 1))
        await rig.settled()
        await s13Until { rig.store.pendingRoute != nil }
        #expect(rig.store.pendingRoute?.route == .day(DayTemplateID(S13IDs.id(1)), weekIndex: 1))
        #expect(try await rig.storedProgram()?.days.count == 5)
    }

    @Test("R1 and criterion 13: a day's write cancelled before storing routes nothing; the next run routes once")
    func addDay_cancelledBeforeStoring_routeAfterTheNextRun() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer { tasks.sources.cancel() }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.addDay(name: "Day 5", weekIndex: 2))
        try await rig.probe.waitUntilHeld()
        tasks.saves.cancel()
        await rig.probe.release()
        await tasks.saves.value
        #expect(rig.store.pendingRoute == nil)
        let again = Task { await rig.store.save() }
        defer { again.cancel() }
        await rig.settled()
        await s13Until { rig.store.pendingRoute != nil }
        #expect(rig.store.pendingRoute?.route == .day(DayTemplateID(S13IDs.id(0)), weekIndex: 2))
        #expect(try await rig.storedProgram()?.days.count == 5)
    }

    @Test("Criterion 7: no active program is the empty state; an observation that ends is the failed state")
    func sources_emptyAndFailed() async throws {
        let empty = try S13Rig(program: .some(nil))
        let emptyTasks = await empty.start()
        #expect(empty.store.state == .noProgram)
        emptyTasks.sources.cancel()
        emptyTasks.saves.cancel()
        let ended = try S13Rig { S13EndingPrograms(base: $0, endings: 1) }
        let endedTasks = await ended.start()
        #expect(ended.store.state == .failed)
        endedTasks.sources.cancel()
        endedTasks.saves.cancel()
        await endedTasks.sources.value
        // A new run reads again, and the failed state stays until the program is shown.
        var seen: [String] = []
        let watcher = Task { @MainActor in
            for await state in Observations({ ended.store.state }) {
                seen.append(Self.phase(state))
            }
        }
        defer { watcher.cancel() }
        let again = await ended.start()
        defer {
            again.sources.cancel()
            again.saves.cancel()
        }
        await s13Until { ended.model != nil }
        #expect(!seen.contains("loading"), "\(seen)")
    }

    static func phase(_ state: ProgramStore.State) -> String {
        switch state {
        case .loading: "loading"
        case .loaded: "loaded"
        case .noProgram: "noProgram"
        case .failed: "failed"
        }
    }
}
