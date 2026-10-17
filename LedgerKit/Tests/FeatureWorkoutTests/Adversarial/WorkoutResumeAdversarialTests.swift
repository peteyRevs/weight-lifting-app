@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4 criterion 3 and rows L2, L3, L5, L29: a live workout is shown from the session whatever
/// became of its day, the use case is not asked for it, and a start that is refused says why.
@MainActor
@Suite("Workout resume and refusals (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutResumeAdversarialTests {
    typealias World = AdversarialWorld

    /// What can become of a live workout's day while the workout runs.
    nonisolated enum Fate: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case dayEmptied, dayDeleted, programDeactivated, programDeleted

        var testDescription: String {
            rawValue
        }

        @MainActor
        func strike(_ world: AdversarialWorld) async throws {
            let id = world.program.id
            let programs = world.stores.programs
            switch self {
            case .dayEmptied:
                _ = try await programs.update(id) { program in
                    var changed = program
                    changed.days[0].slots = []
                    return changed
                }
            case .dayDeleted:
                _ = try await programs.update(id) { program in
                    var changed = program
                    let gone = changed.days.removeFirst().id
                    for index in changed.weeks.indices {
                        changed.weeks[index].schedule = changed.weeks[index].schedule.filter { $0.value != gone }
                    }
                    return changed
                }
            case .programDeactivated:
                _ = try await programs.update(id) { program in
                    var changed = program
                    changed.isActive = false
                    return changed
                }
            case .programDeleted:
                try await programs.delete(id)
            }
        }
    }

    @Test(
        "L5: a live workout whose day or program is gone is shown, by its day and by resume, without the use case",
        arguments: World.Kind.allCases, Fate.allCases
    )
    func liveWorkout_dayGone_isStillShown(kind: World.Kind, fate: Fate) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            try await fate.strike(world)
            let rig = AdversarialRig()
            let before = await world.useCaseStarts()

            await rig.start(world.source(day: 0))
            #expect(rig.phase == .cover, "\(rig.phase)")
            #expect(rig.shown?.id == first.id)
            await rig.tap(.minimize)
            await rig.start(world.source(day: 0))
            #expect(rig.shown?.id == first.id, "asked again, it shows again")
            await rig.tap(.minimize)
            await rig.resume()
            #expect(rig.shown?.id == first.id)

            #expect(await world.useCaseStarts() == before, "StartWorkoutUseCase.start was called for a live workout")
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
            #expect(try await unchanged(world.live(), first))
        }
    }

    @Test(
        "L2: with nothing live, a day that cannot be started starts nothing and the lifter is told why",
        arguments: World.Kind.allCases, Fate.allCases
    )
    func nothingLive_dayGone_isRefusedWithItsReason(kind: World.Kind, fate: Fate) async throws {
        try await World.run(kind) { world in
            try await fate.strike(world)
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let reason: WorkoutLaunchFailure.Reason = fate == .dayEmptied ? .emptyDay : .dayNotInProgram
            #expect(rig.phase == .failed(.notStarted(reason)), "\(rig.phase)")
            #expect(rig.covers == 0)
            let live = try await world.live()
            #expect(live?.id == nil)
            #expect(await world.session.count(.start) == 0)
            await rig.answer(.dismissFailure)
            #expect(rig.phase == .idle)
        }
    }

    @Test("L2: a week past the block's end starts nothing and says the block has ended", arguments: World.Kind.allCases)
    func nothingLive_weekPastTheBlock_saysTheBlockEnded(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0, week: world.program.weeks.count))
            #expect(rig.phase == .failed(.notStarted(.blockEnded)), "\(rig.phase)")
            let live = try await world.live()
            #expect(live?.id == nil)
        }
    }

    @Test("A live workout of a week past the block's end is still shown by its own day", arguments: World.Kind.allCases)
    func liveWorkout_asOtherWeek_isAConflictNotARefusal(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            // The same day in another week is another source: the lifter is asked, never refused.
            await rig.start(world.source(day: 0, week: 1))
            #expect(rig.phase == .conflict(world.source(day: 0, week: 1)), "\(rig.phase)")
            await rig.answer(.resumeLive)
            #expect(rig.shown?.id == first.id)
        }
    }
}
