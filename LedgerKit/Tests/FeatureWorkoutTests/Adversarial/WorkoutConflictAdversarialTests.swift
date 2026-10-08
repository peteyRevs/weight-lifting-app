@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4 criterion 4: the conflict's order and its failures (rows L12 to L17 of the tester's table).
/// A workout the lifter did not agree to lose is never lost, nothing starts when the discard fails, and the
/// lifter is told what is left.
@MainActor
@Suite("Workout conflict (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutConflictAdversarialTests {
    typealias World = AdversarialWorld

    /// A live on day 0, the dialog up for day 1.
    func asked(_ world: World) async throws -> (rig: AdversarialRig, first: WorkoutState) {
        let first = try await world.begin(day: 0)
        let rig = AdversarialRig()
        await rig.start(world.source(day: 1))
        #expect(rig.phase == .conflict(world.source(day: 1)))
        await world.session.clearCalls()
        return (rig, first)
    }

    func message(_ rig: AdversarialRig) -> String {
        guard case let .failed(failure) = rig.phase else {
            return "no alert (\(rig.phase))"
        }
        let alert = WorkoutPresentation.alert(for: failure)
        return "\(alert.title) / \(alert.message) / \(alert.dismiss)"
    }

    @Test(
        "L12: when the discard fails nothing starts, the old workout is live and the lifter is told",
        arguments: World.Kind.allCases
    )
    func replace_discardFails_keepsTheOldWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            await world.session.fail(.discard)
            await rig.answer(.replaceLive(world.source(day: 1)))
            #expect(await world.session.count(.start) == 0)
            #expect(try await unchanged(world.live(), first))
            #expect(rig.covers == 0)
            #expect(message(rig) == "Couldn't start the new workout / Your workout in progress was kept. / OK")

            await rig.answer(.dismissFailure)
            #expect(rig.phase == .idle)
            await rig.resume()
            #expect(rig.shown?.id == first.id, "the kept workout is reachable")
        }
    }

    @Test(
        "L13: when the start fails after the discard, nothing is live and the lifter is told so",
        arguments: World.Kind.allCases
    )
    func replace_startFails_saysTheOldOneIsGone(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, _) = try await asked(world)
            await world.session.fail(.start)
            await rig.answer(.replaceLive(world.source(day: 1)))
            let live = try await world.live()
            #expect(live?.id == nil)
            #expect(rig.covers == 0)
            #expect(message(rig) == "Couldn't start the new workout / Your workout in progress was discarded. / OK")
            let order = await world.session.calls.filter { $0 == .discard || $0 == .start }
            #expect(order == [.discard, .start])

            await rig.answer(.dismissFailure)
            await rig.start(world.source(day: 1))
            #expect(rig.phase == .cover)
            #expect(rig.shown?.source == world.source(day: 1))
        }
    }

    @Test(
        "A start whose answer is lost after the discard shows the new workout, which is live",
        arguments: World.Kind.allCases
    )
    func replace_startAnswerLost_showsTheNewWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            await world.session.fail(.start, afterwards: true)
            await rig.answer(.replaceLive(world.source(day: 1)))
            let live = try #require(try await world.live())
            #expect(live.id != first.id)
            #expect(live.source == world.source(day: 1))
            #expect(rig.phase == .cover, "\(message(rig))")
            #expect(rig.shown?.id == live.id)
        }
    }

    @Test(
        "A discard whose answer is lost: the old workout is gone, nothing started, and the lifter is told that",
        arguments: World.Kind.allCases
    )
    func replace_discardAnswerLost_saysTheOldOneIsGone(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, _) = try await asked(world)
            await world.session.fail(.discard, afterwards: true)
            await rig.answer(.replaceLive(world.source(day: 1)))
            let live = try await world.live()
            #expect(live?.id == nil)
            #expect(await world.session.count(.start) == 0)
            #expect(message(rig) == "Couldn't start the new workout / Your workout in progress was discarded. / OK")
        }
    }

    @Test(
        "L14: a new day that cannot be built leaves the old workout live, with no discard",
        arguments: World.Kind.allCases
    )
    func replace_newDayEmptied_keepsTheOldWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            _ = try await world.stores.programs.update(world.program.id) { program in
                var changed = program
                changed.days[1].slots = []
                return changed
            }
            await rig.answer(.replaceLive(world.source(day: 1)))
            #expect(await world.session.count(.discard) == 0)
            #expect(await world.session.count(.start) == 0)
            #expect(try await unchanged(world.live(), first))
            #expect(message(rig) == "Couldn't start the new workout / Your workout in progress was kept. / OK")
        }
    }

    @Test(
        "L17: the dialog's choice applied twice, and with its dismissal in either order, is done once",
        arguments: World.Kind.allCases
    )
    func replace_twice_isDoneOnce(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            rig.launcher.send(.replaceLive(world.source(day: 1)))
            rig.launcher.send(.replaceLive(world.source(day: 1)))
            rig.launcher.send(.cancelConflict)
            await rig.settle()
            #expect(await world.session.count(.discard) == 1)
            #expect(await world.session.count(.start) == 1)
            #expect(rig.phase == .cover)
            #expect(rig.shown?.source == world.source(day: 1))
            #expect(rig.shown?.id != first.id)
            #expect(rig.covers == 1)
        }
    }
}
