@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: a write that fails for any reason but its task's cancellation (criterion 5): every
/// waiting edit, sent or not, is dropped, the stored program is drawn, and the notice's line says so.
@MainActor
@Suite("Adversarial F11 S13 · a write refused or lost", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramSaveFailuresAdversarialTests {
    @Test("A refused write drops the edit sent and the two queued behind it, shows the stored program, says so")
    func refusedWrite_dropsEveryWaitingEdit() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let original = try #require(rig.session.shown)
        await rig.probe.hold(.updateProgram)
        await rig.probe.fail(.updateProgram)
        rig.store.send(.rename("Sent"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.addWeek(selecting: 8))
        rig.store.send(.edit(.setDeload(true, week: 1)))
        await rig.probe.release()
        await rig.settled()
        #expect(rig.session.waiting.isEmpty)
        #expect(rig.session.shown == original)
        #expect(rig.store.notice == .saveFailed)
        #expect(rig.model?.notice == "That change wasn't saved. Try again.")
        #expect(rig.model?.block.chips.count == 8)
        #expect(await rig.updates() == 1, "the edits queued behind it are never sent")
        // Then an edit is stored as usual and the line goes.
        rig.store.send(.edit(.setDeload(true, week: 2)))
        #expect(rig.store.notice == nil, "every other edit drops the notice")
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored == s13OneAtATime([.setDeload(true, week: 2)], to: original))
        #expect(rig.store.notice == nil)
        #expect(rig.session.shown == stored)
    }

    @Test("A prepare that throws (the logged weeks not read before a \"−\") fails the write; nothing is sent")
    func prepareThrows_isAFailedWrite() async throws {
        let rig = try S13SessionRig<ProgramBuilderEdit>(program: Fixtures.seedProgram())
        #expect(rig.session.enqueue(.removeLastWeek(loggedWeeks: [])))
        let outcomes = S13Outcomes()
        let loop = Task {
            await rig.session.run(prepare: { _ in throw S13Refused() }, finished: { outcomes.append($0) })
        }
        defer { loop.cancel() }
        await s13Until { rig.session.isIdle }
        #expect(outcomes.names == ["failed"])
        #expect(rig.session.shown?.weeks.count == 8)
        #expect(await rig.updates() == 0, "nothing reaches the store")
    }

    @Test("An acknowledgement lost after the store stored the edit: the screen ends on what the store holds")
    func lostAcknowledgement_screenEndsOnWhatIsStored() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram, afterStoring: true)
        await rig.probe.fail(.updateProgram, afterStoring: true)
        rig.store.send(.addWeek(selecting: 8))
        try await rig.probe.waitUntilHeld()
        // The store has stored the nine weeks and emitted them; the session hears them during the write.
        await s13Until { rig.session.heardDuringWrite != nil }
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.weeks.count == 9, "the probe let the store keep it")
        #expect(rig.store.notice == .saveFailed)
        #expect(
            rig.session.shown == stored,
            "the screen shows \(rig.session.shown?.weeks.count ?? 0) weeks of 9 stored"
        )
        #expect(rig.session.stored == stored)
    }
}
