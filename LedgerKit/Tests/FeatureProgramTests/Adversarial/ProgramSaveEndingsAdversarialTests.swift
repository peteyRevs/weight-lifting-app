@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: how a write ends (criteria 5 and 6, ruling R1). Cancelled before it stored, its
/// edits stay and are sent once by the next run; cancelled after it stored, they are not sent again; any other
/// failure drops every waiting edit, sent or not, and says so in the notice's line.
@MainActor
@Suite("Adversarial F11 S13 · a write cancelled", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramSaveEndingsAdversarialTests {
    // MARK: R1, cancelled

    @Test("R1: the save task cancelled while its write waits before the store: the week is kept, then added once")
    func cancelledBeforeStoring_keepsTheEdits_andTheNextRunAddsTheWeekOnce() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer { tasks.sources.cancel() }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.addWeek(selecting: 8))
        rig.store.send(.rename("Kept"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.edit(.setDeload(true, week: 2)))
        tasks.saves.cancel()
        await rig.probe.release()
        await tasks.saves.value
        #expect(try await rig.storedProgram()?.weeks.count == 8, "nothing was stored")
        #expect(rig.session.waiting.count == 3, "every edit still waits, the sent ones at the front")
        #expect(rig.session.shown?.weeks.count == 9)
        #expect(rig.session.shown?.name == "Kept")
        #expect(rig.store.notice == nil, "nothing is shown as failed")
        let again = Task { await rig.store.save() }
        defer { again.cancel() }
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.weeks.count == 9, "the week is added once")
        #expect(stored.name == "Kept")
        #expect(stored.week(at: 2)?.isDeload == true)
        #expect(stored.weeks.last?.id == WeekID(S13IDs.id(0)))
        #expect(rig.session.shown == stored)
        #expect(await rig.updates() == 2, "the cancelled call, then one call with the three edits")
    }

    @Test("R1: cancelled once the store has stored it: the call returns, its edits are dropped and never resent")
    func cancelledAfterStoring_dropsTheEdits_andSendsNothingAgain() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer { tasks.sources.cancel() }
        await rig.probe.hold(.updateProgram, afterStoring: true)
        rig.store.send(.addWeek(selecting: 8))
        try await rig.probe.waitUntilHeld()
        tasks.saves.cancel()
        await rig.probe.release()
        await tasks.saves.value
        #expect(rig.session.waiting.isEmpty, "the stored edit is not kept")
        #expect(rig.store.notice == nil)
        let again = Task { await rig.store.save() }
        defer { again.cancel() }
        rig.store.send(.rename("After"))
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.weeks.count == 9, "the week is added once")
        #expect(stored.name == "After")
        #expect(await rig.updates() == 2)
        #expect(rig.session.shown == stored)
    }

    @Test("R1 with TaskCancelSwitch: cancelled just before update, at the session's own prepare; kept, sent once")
    func cancelledInPrepare_keepsTheEdits() async throws {
        let program = try Fixtures.seedProgram()
        let rig = try S13SessionRig<ProgramBuilderEdit>(program: program)
        let cancel = TaskCancelSwitch()
        #expect(rig.session.enqueue(.addWeek(WeekID(Fixtures.uuid(81000)))))
        let outcomes = S13Outcomes()
        let first = cancel.run { @MainActor in
            await rig.session.run(
                prepare: { edits in
                    cancel.fire()
                    return edits
                },
                finished: { outcomes.append($0) }
            )
        }
        _ = await first.result
        #expect(outcomes.names == [], "a write that stored nothing because its task ended reports no outcome")
        #expect(rig.session.waiting.count == 1)
        #expect(try await rig.memory.programs.active()?.weeks.count == 8)
        let second = Task { await rig.session.run { outcomes.append($0) } }
        defer { second.cancel() }
        await s13Until { rig.session.isIdle }
        #expect(try await rig.memory.programs.active()?.weeks.count == 9)
        #expect(outcomes.names == ["stored"])
    }

    @Test("A CancellationError thrown while the task runs on is a failure: the edits are dropped, sent once, and said")
    func cancellationErrorWithoutCancellation_isAFailure_notALoop() async throws {
        var throwing: S13ThrowingPrograms?
        let rig = try S13Rig { base in
            let made = S13ThrowingPrograms(base: base, times: 3) { CancellationError() }
            throwing = made
            return made
        }
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        rig.store.send(.addWeek(selecting: 8))
        await rig.settled()
        #expect(throwing?.calls == 1, "the loop does not send the edits again while its task runs")
        #expect(rig.session.waiting.isEmpty)
        #expect(rig.store.notice == .saveFailed)
        #expect(try await rig.storedProgram()?.weeks.count == 8)
    }
}

/// A test's error.
nonisolated struct S13Refused: Error {}

/// The outcomes a session's `finished` was handed, by name.
@MainActor
final class S13Outcomes {
    private(set) var names: [String] = []

    func append(_ outcome: ProgramEditSession<ProgramBuilderEdit>.Outcome) {
        switch outcome {
        case .stored: names.append("stored")
        case .failed: names.append("failed")
        }
    }
}
