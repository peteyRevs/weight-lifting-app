@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: the save loop's pinned cases (criteria 1, 4 and 11): edits made during a write go
/// together in the next, typing against a held write, and edits that change nothing (ruling R7).
@MainActor
@Suite("Adversarial F11 S13 · the save loop, pinned", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramSaveLoopPinnedAdversarialTests {
    @Test("Three edits made while the first write is held go together in the second, and nothing else is written")
    func editsMadeDuringAWrite_goTogetherInTheNext() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let start = try #require(rig.session.shown)
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("A"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.addWeek(selecting: 8))
        rig.store.send(.edit(.setDeload(true, week: 1)))
        rig.store.send(.rename("AB"))
        #expect(rig.session.waiting.count == 4, "the one in flight and three behind it")
        await rig.probe.release()
        await rig.settled()
        let expected = s13OneAtATime(
            [.renameProgram("A"), .addWeek(WeekID(S13IDs.id(0))), .setDeload(true, week: 1), .renameProgram("AB")],
            to: start
        )
        #expect(try await rig.storedProgram() == expected)
        #expect(await rig.updates() == 2)
        #expect(rig.session.shown == expected)
    }

    @Test("Ten letters typed against a held write are two writes, and the name stored is the last one typed")
    func tenLetters_heldWrite_twoWrites() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        let text = "Upper Lowe"
        for count in 1 ... text.count {
            rig.store.send(.rename(String(text.prefix(count))))
            // The stored name is cleaned ("Upper " is "Upper"); the field's draft keeps the space.
            #expect(rig.model?.header.name == String(text.prefix(count)).trimmingCharacters(in: .whitespaces))
            if count == 1 {
                try await rig.probe.waitUntilHeld()
            }
        }
        await rig.probe.release()
        await rig.settled()
        #expect(await rig.updates() == 2)
        #expect(try await rig.storedProgram()?.name == "Upper Lowe")
    }

    @Test(
        "R7: an edit taking the screen back to the stored value, made during a write, is written"
    )
    func backToTheStoredName_duringAWrite_isWritten() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let original = try #require(rig.session.shown?.name)
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("Other"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.rename(original))
        #expect(rig.model?.header.name == original)
        await rig.probe.release()
        await rig.settled()
        #expect(try await rig.storedProgram()?.name == original, "the lifter's last text is the one stored")
        #expect(await rig.updates() == 2)
    }

    @Test("R7: a rename to the stored name, a blank one, a deload already set and a cell already so write nothing")
    func noOpEdits_writeNothing() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let program = try #require(rig.session.shown)
        let week = try #require(program.week(at: 1))
        let monday = week.schedule[.monday]
        rig.store.send(.rename(program.name))
        rig.store.send(.rename("   "))
        rig.store.send(.rename(""))
        rig.store.send(.edit(.setDeload(false, week: 1)))
        rig.store.send(.edit(.setDeload(true, week: 7)))
        rig.store.send(.edit(.setSchedule(week: 1, weekday: .monday, day: monday)))
        rig.store.send(.edit(.setSchedule(week: 40, weekday: .monday, day: nil)))
        rig.store.send(.edit(.setSchedule(week: 1, weekday: .tuesday, day: DayTemplateID(Fixtures.uuid(99999)))))
        rig.store.send(.edit(.copyPreviousWeek(week: 0)))
        #expect(rig.session.waiting.isEmpty)
        #expect(rig.session.isIdle)
        // A real edit afterwards is the first write.
        rig.store.send(.edit(.setDeload(true, week: 1)))
        await rig.settled()
        #expect(await rig.updates() == 1)
    }
}
