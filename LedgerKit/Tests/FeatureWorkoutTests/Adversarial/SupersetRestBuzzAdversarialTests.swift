@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// G2, F10 S9 ruling Q4 on one phone (`RestCover`: the real host, the cover's tasks as `WorkoutRoot` runs
/// them, haptics that record, time the test moves): a member logged while the group's rest runs ends it, so the
/// panel goes and no "Rest over" buzz comes in the middle of the round, and an un-log of that member brings
/// neither back. The workout is Upper A, whose Lat Pulldown (3) and Cable Lateral Raise (4) are a superset
/// resting 75 s.
@MainActor
@Suite("Superset rest and its buzz (adversarial, F10 S9)", .tags(.feature), .timeLimit(.minutes(2)))
struct SupersetRestBuzzAdversarialTests {
    static func set(_ workout: WorkoutState, _ exercise: Int, _ row: Int) -> SetID {
        workout.exercises[exercise].sets[row].id
    }

    @Test("Control: after A1 B1 the group's rest runs out and buzzes once")
    func control_restOverBuzzes() async throws {
        let running = try Fixtures.seedSession()
        let cover = try await RestCover(running)
        await cover.tap(.jump(exerciseIndex: 3))
        await cover.tap(.log(exerciseIndex: 3, setID: Self.set(running, 3, 0)))
        await cover.tap(.log(exerciseIndex: 4, setID: Self.set(running, 4, 0)))
        #expect(cover.panel?.next?.line.hasPrefix("A2 · ") == true)
        await cover.run(80)
        #expect(cover.panel?.isOver == true)
        let buzzes = await cover.played().count { $0 == .restOver }
        #expect(buzzes == 1)
        await cover.close()
    }

    @Test("A2 logged during the rest: the panel goes, and no Rest over buzz comes; un-logging A2 brings none back")
    func memberDuringRest_noBuzz_andUnlogBringsNone() async throws {
        let running = try Fixtures.seedSession()
        let cover = try await RestCover(running)
        await cover.tap(.jump(exerciseIndex: 3))
        await cover.tap(.log(exerciseIndex: 3, setID: Self.set(running, 3, 0)))
        await cover.tap(.log(exerciseIndex: 4, setID: Self.set(running, 4, 0)))
        await cover.run(30)
        #expect(cover.panel != nil)
        await cover.tap(.log(exerciseIndex: 3, setID: Self.set(running, 3, 1)))
        #expect(cover.panel == nil, "the member ended the rest")
        #expect(await cover.panelFault() == nil)
        await cover.run(120)
        #expect(cover.panel == nil)
        await cover.run(5)
        await cover.tap(.unlog(exerciseIndex: 3, setID: Self.set(running, 3, 1)))
        #expect(cover.panel == nil, "the un-log brings no rest back")
        await cover.run(200)
        let played = await cover.played()
        #expect(played.count { $0 == .restOver } == 0, "no Rest over during the round: \(played)")
        #expect(played.count { $0 == .setLogged } == 3)
        await cover.close()
    }

    @Test("A2 logged after Rest over: the ended panel goes and never buzzes again; a reopened cover shows none")
    func memberAfterRestOver_endsIt_andReopenShowsNone() async throws {
        let running = try Fixtures.seedSession()
        let cover = try await RestCover(running)
        await cover.tap(.jump(exerciseIndex: 3))
        await cover.tap(.log(exerciseIndex: 3, setID: Self.set(running, 3, 0)))
        await cover.tap(.log(exerciseIndex: 4, setID: Self.set(running, 4, 0)))
        await cover.run(90)
        #expect(cover.panel?.isOver == true)
        await cover.tap(.log(exerciseIndex: 3, setID: Self.set(running, 3, 1)))
        #expect(cover.panel == nil)
        await cover.reopen()
        #expect(cover.panel == nil, "a cover that comes up again shows no ended rest")
        let block = try #require(cover.store.model.page?.block)
        #expect(block.title == "Round 2 of 3")
        #expect(block.rows.first { $0.state == .active }?.label == "B2")
        await cover.run(300)
        #expect(await cover.played().count { $0 == .restOver } == 1, "only the one that was owed")
        await cover.close()
    }
}
