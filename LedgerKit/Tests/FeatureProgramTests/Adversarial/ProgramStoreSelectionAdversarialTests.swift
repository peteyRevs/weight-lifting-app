@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: the selected week (criteria 9 and 10) and the notice (criterion 12).
@MainActor
@Suite("Adversarial F11 S13 · the selected week and the notice", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramStoreSelectionAdversarialTests {
    @Test("Criterion 9: the first model selects the week that holds today (week 5 of the seed on 2026-09-16)")
    func firstLoad_selectsTodaysWeek() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        #expect(rig.store.selectedWeek == 4)
        #expect(rig.model?.block.selectedPlaces == [4])
    }

    @Test("Criterion 9: a week asked for before the program arrives wins over today's")
    func requestedBeforeTheProgram_wins() async throws {
        let rig = try S13Rig()
        rig.store.select(week: 6)
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        #expect(rig.store.selectedWeek == 6)
    }

    @Test("Criterion 9 on a day before the block: today's week is handed raw, and the model shows the first")
    func todayBeforeTheBlock_isHandedRaw() async throws {
        let rig = try S13Rig(now: Fixtures.date(2026, 8, 1, hour: 9))
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        #expect((rig.store.selectedWeek ?? 0) < 0, "raw: \(String(describing: rig.store.selectedWeek))")
        #expect(rig.model?.block.chips.first?.isSelected == true)
    }

    @Test("Criterion 10: the same \"+\" sent twice from one model adds two weeks and selects the second")
    func addWeek_sameActionTwice_selectsTheWeekItAdded() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        let plus = try #require(rig.model?.block.addWeek)
        rig.store.send(plus)
        rig.store.send(plus)
        #expect(rig.session.shown?.weeks.count == 10)
        #expect(rig.store.selectedWeek == 9, "the week the second tap added")
        try await rig.probe.waitUntilHeld()
        await rig.probe.release()
        await rig.settled()
        let added = try await rig.storedProgram()?.weeks.map(\.id).suffix(2)
        #expect(added == [WeekID(S13IDs.id(0)), WeekID(S13IDs.id(1))])
    }

    @Test("Criterion 9: after \"−\" on the selected last week the selection is kept raw, the last week shown")
    func minusOnTheSelectedLastWeek_keepsTheSelectionRaw() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        rig.store.send(.selectWeek(7))
        let minus = try #require(rig.model?.block.removeWeek)
        rig.store.send(minus)
        #expect(rig.store.selectedWeek == 7)
        #expect(rig.model?.block.chips.last?.isSelected == true)
        await rig.settled()
    }

    @Test("Criterion 12: a notice is replaced by one carried, dropped by another edit and by a week's selection")
    func notice_replacedAndDropped() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        rig.store.send(.notice(.minimumTwoWeeks))
        #expect(rig.store.notice == .minimumTwoWeeks)
        rig.store.send(.edit(.setDeload(true, week: 1), notice: .dayHasNoExercises))
        #expect(rig.store.notice == .dayHasNoExercises)
        rig.store.send(.rename("Next"))
        #expect(rig.store.notice == nil)
        rig.store.send(.notice(.minimumTwoWeeks))
        rig.store.send(.selectWeek(2))
        #expect(rig.store.notice == nil)
        await rig.probe.fail(.updateProgram)
        rig.store.send(.rename("Refused"))
        await rig.settled()
        #expect(rig.store.notice == .saveFailed)
        rig.store.send(.selectWeek(3))
        #expect(rig.store.notice == nil)
    }
}
