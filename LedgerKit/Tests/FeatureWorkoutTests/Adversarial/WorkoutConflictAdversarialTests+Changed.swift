@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The world changed while the dialog showed, and requests that overlap it.
extension WorkoutConflictAdversarialTests {
    @Test("The dialog's dismissal arriving before its choice does not lose the choice", arguments: World.Kind.allCases)
    func dismissalFirst_thenChoice_stillActs(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            rig.launcher.send(.cancelConflict)
            rig.launcher.send(.resumeLive)
            await rig.settle()
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == first.id)
            #expect(await world.session.count(.discard) == 0)
        }
    }

    @Test(
        "L15: the live workout finished elsewhere while the dialog shows; \"Resume it\" shows no dead workout",
        arguments: World.Kind.allCases
    )
    func endedWhileAsked_resumeIt_showsNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(30))
            await rig.answer(.resumeLive)
            #expect(rig.shown?.id == nil)
            #expect(rig.phase == .idle, "\(rig.phase)")
            #expect(rig.routes.isEmpty, "a cover that showed nothing has no route to report")
            let live = try await world.live()
            #expect(live?.id == nil)
            #expect(await world.session.count(.discard) == 0)
            if kind == .host {
                let saved = try await world.stores.workouts.workout(id: first.id)
                #expect(saved?.id == first.id)
            }
        }
    }

    @Test(
        "L16: finished elsewhere while the dialog shows; \"Discard and start new\" starts, and history keeps the first",
        arguments: World.Kind.allCases
    )
    func endedWhileAsked_replace_startsAndKeepsHistory(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(30))
            await rig.answer(.replaceLive(world.source(day: 1)))
            let live = try #require(try await world.live())
            #expect(live.source == world.source(day: 1))
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == live.id)
            if kind == .host {
                let saved = try await world.stores.workouts.workout(id: first.id)
                #expect(saved?.phase == .finished)
            }
        }
    }

    @Test(
        "The asked day became the live one while the dialog shows: \"Discard and start new\" discards nothing",
        arguments: World.Kind.allCases
    )
    func askedDayBecameLive_replace_resumesIt(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, _) = try await asked(world)
            let second = try await world.begin(day: 1, replacingLive: true)
            await rig.answer(.replaceLive(world.source(day: 1)))
            #expect(await world.session.count(.discard) == 0, "the lifter agreed to lose day 0's workout, not day 1's")
            #expect(try await world.live()?.id == second.id)
            #expect(rig.shown?.id == second.id)
        }
    }

    @Test(
        "\"Resume it\" when the session cannot be read: nothing is shown, the workout is live, the lifter is told",
        arguments: World.Kind.allCases
    )
    func resumeIt_sessionUnreadable_isTold(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            await world.session.fail(.current, times: 5)
            await rig.answer(.resumeLive)
            #expect(message(rig) == "Couldn't open this workout / Try again. / OK")
            #expect(rig.covers == 0)
            await world.session.heal()
            #expect(try await unchanged(world.live(), first))
            await rig.answer(.dismissFailure)
            await rig.resume()
            #expect(rig.shown?.id == first.id)
        }
    }

    @Test(
        "While \"Discard and start new\" runs, no other request is taken and the cover stays down",
        arguments: World.Kind.allCases
    )
    func replaceInFlight_takesNoOtherRequest(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let (rig, first) = try await asked(world)
            await world.session.hold(.discard)
            rig.launcher.send(.replaceLive(world.source(day: 1)))
            let running = Task { await rig.launcher.run() }
            await world.session.waitUntilHeld()
            #expect(rig.phase == .working)
            #expect(try await world.live()?.id == first.id, "held before the discard: the old workout is still live")
            rig.launcher.resume()
            rig.launcher.start(world.source(day: 2))
            rig.launcher.send(.resumeLive)
            await rig.launcher.run()
            #expect(rig.phase == .working)
            await world.session.release()
            await running.value
            await rig.settle()
            #expect(await world.session.count(.discard) == 1)
            #expect(await world.session.count(.start) == 1)
            #expect(rig.shown?.source == world.source(day: 1))
            #expect(rig.covers == 1)
        }
    }

    /// Finding F10-S4-3, closed by criterion 15 (round 2): the lifter is told why the new day did not start,
    /// as the same day asked for with nothing live is told. Whatever the words, nothing is discarded.
    @Test("A day past the block's end asked over a live workout: the dialog shows, and replacing discards nothing")
    func replace_weekPastTheBlock_keepsTheOldWorkout() async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            let late = world.source(day: 1, week: world.program.weeks.count)
            await rig.start(late)
            #expect(rig.phase == .conflict(late), "\(rig.phase)")
            await world.session.clearCalls()
            await rig.answer(.replaceLive(late))
            #expect(rig.phase == .failed(.notStarted(.blockEnded)), "\(rig.phase)")
            #expect(await world.session.count(.discard) == 0)
            #expect(try await unchanged(world.live(), first))
        }
    }
}
