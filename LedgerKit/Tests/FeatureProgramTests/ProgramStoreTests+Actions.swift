@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13, criteria 10 and 11: the brief's worked examples of criteria 2 to 5, tapped on the model the real
/// store shows (review N-8), and the name as it is typed.
extension ProgramStoreTests {
    // MARK: Criterion 10

    @Test("10. Brief 2: Tuesday of week 1 tapped five times reads UA, LA, UB, LB, REST, and the chip counts it")
    func tuesdayTappedFiveTimes_cyclesAndCounts() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        scene.store.send(.selectWeek(0))
        var read: [String] = []
        for _ in 0 ..< 5 {
            try scene.store.send(#require(scene.model.week.cell(.tuesday)?.action))
            try read.append("\(#require(scene.model.week.cell(.tuesday)).label) \(scene.model.block.chips[0].subtitle)")
        }
        #expect(read == ["UA 5 DAYS", "LA 5 DAYS", "UB 5 DAYS", "LB 5 DAYS", "REST 4 DAYS"])
        await scene.idle()
        #expect(try await scene.stored().weeks[0].schedule[.tuesday] == nil)
        await running.cancel()
    }

    @Test("10. Brief 3: copy week 2 into week 3, apply it to later weeks with the deloads kept, make week 3 a deload")
    func copyApplyAndDeload_asTheBriefSays() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        scene.store.send(.selectWeek(1))
        try scene.store.send(#require(scene.model.week.cell(.tuesday)?.action))
        let second = try scene.model.week.strip
        scene.store.send(.selectWeek(2))
        try scene.store.send(#require(scene.model.week.copyPrevious.action))
        #expect(try scene.model.week.strip == second)
        try scene.store.send(#require(scene.model.week.applyToLater?.action))
        try scene.store.send(scene.model.week.deload.action)
        #expect(try scene.model.block.chips[2].subtitle == "DELOAD")
        await scene.idle()
        let stored = try await scene.stored()
        #expect(stored.weeks[2 ... 7].allSatisfy { $0.schedule == stored.weeks[1].schedule })
        #expect(stored.weeks.map(\.isDeload) == [false, false, true, false, false, false, false, true])
        await running.cancel()
    }

    @Test("10. Brief 4: \"−\" at two weeks says so and changes nothing; \"+\" appends the last week, selected")
    func removeWeek_atTwoWeeks_showsTheMessage_andChangesNothing() async throws {
        var program = try Fixtures.seedProgram()
        program.weeks.removeLast(6)
        let scene = try ProgramStoreScene(program: program)
        let running = await scene.running()
        try scene.store.send(scene.model.block.removeWeek)
        #expect(try scene.model.notice == "A block needs at least 2 weeks.")
        #expect(try scene.model.block.chips.count == 2 && scene.store.session.waiting.isEmpty)
        try scene.store.send(scene.model.block.addWeek)
        #expect(try scene.model.block.chips.map(\.isSelected) == [false, false, true])
        #expect(try scene.model.notice == nil)
        await scene.idle()
        let stored = try await scene.stored()
        #expect(stored.weeks.count == 3 && !stored.weeks[2].isDeload)
        #expect(stored.weeks[2].schedule == stored.weeks[1].schedule)
        #expect(await scene.writes() == 1)
        await running.cancel()
    }

    @Test("10. Two quick \"+\" from one model add two weeks: each draws its id at the tap")
    func addWeek_twiceFromOneModel_addsTwoWeeks() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let plus = try scene.model.block.addWeek
        scene.store.send(plus)
        scene.store.send(plus)
        #expect(try scene.model.block.title == "BLOCK · 10 WEEKS")
        await scene.idle()
        #expect(try await scene.stored().weeks.count == 10)
        await running.cancel()
    }

    @Test("10. Brief 5: \"+ Add training day\" adds New day, D5, with no exercise, and opens it once stored")
    func addDay_isNamedAndTagged_andOpens() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        try scene.store.send(#require(scene.model.days.addDay.action))
        let card = try #require(scene.model.days.cards.last)
        #expect(card.name == "New day" && card.tag == "D5" && card.meta == "No exercises yet")
        await eventually { scene.store.pendingRoute != nil }
        #expect(scene.store.pendingRoute?.route == .day(card.id, weekIndex: 4))
        #expect(try await scene.stored().days.last?.slots.isEmpty == true)
        await running.cancel()
    }

    // MARK: Criterion 11

    @Test("11. \"Upper Lower\" sent letter by letter, the space too, is stored as typed; the header follows")
    func name_typedLetterByLetter_isStored() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let typed = "Upper Lower"
        for end in typed.indices.dropFirst() + [typed.endIndex] {
            scene.store.send(.rename(String(typed[..<end])))
            #expect(try scene.model.header.name == String(typed[..<end]).trimmingCharacters(in: .whitespaces))
        }
        await scene.idle()
        #expect(try await scene.stored().name == "Upper Lower")
        await running.cancel()
    }

    @Test("11. Ten letters typed against a held write are two writes")
    func name_tenLettersAgainstAHeldWrite_areTwoWrites() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        let typed = "Hypertroph"
        scene.store.send(.rename("H"))
        try await scene.probe.waitUntilHeld()
        for end in typed.indices.dropFirst(2) + [typed.endIndex] {
            scene.store.send(.rename(String(typed[..<end])))
        }
        await scene.probe.release()
        await scene.idle()
        #expect(await scene.writes() == 2)
        #expect(try await scene.stored().name == typed)
        await running.cancel()
    }

    @Test("11. A name changed elsewhere while the field is edited is overwritten by the next keystroke")
    func nameChangedElsewhere_isOverwrittenByTheNextKeystroke() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        scene.store.send(.rename("Upper Lowe"))
        await scene.idle()
        let id = try await scene.stored().id
        _ = try await scene.memory.programs.update(id) { ProgramEditing.renameProgram($0, to: "From the watch") }
        await eventually { scene.store.session.stored?.name == "From the watch" }
        scene.store.send(.rename("Upper Lower"))
        await scene.idle()
        #expect(try await scene.stored().name == "Upper Lower")
        await running.cancel()
    }
}
