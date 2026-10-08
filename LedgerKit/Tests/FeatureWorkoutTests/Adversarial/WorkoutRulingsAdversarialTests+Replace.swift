@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criteria 15 and 16 after "Discard and start new": the reason is said, and no line claims what is not known.
extension WorkoutRulingsAdversarialTests {
    nonisolated enum ReplaceFault: String, Sendable, CaseIterable {
        case discard, discardAnswerLost, start, startAnswerLost, programStore
    }

    @Test(
        "A failed replacement says what the session shows, and \"Try again.\" alone when it cannot be read",
        arguments: ReplaceFault.allCases, [true, false]
    )
    func failedReplacement_claimsOnlyWhatIsKnown(fault: ReplaceFault, readable: Bool) async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await rig.start(world.source(day: 1))
            await world.session.clearCalls()
            switch fault {
            case .discard: await world.session.fail(.discard)
            case .discardAnswerLost: await world.session.fail(.discard, afterwards: true)
            case .start: await world.session.fail(.start)
            case .startAnswerLost: await world.session.fail(.start, afterwards: true)
            case .programStore: await world.launcherStores.fail(.activeProgram)
            }
            if !readable {
                // The use case's own read is let through; the read after the failure is not.
                await world.session.fail(.current, times: 9, skipping: fault == .programStore ? 0 : 1)
            }
            await rig.answer(.replaceLive(world.source(day: 1)))
            await world.session.heal()
            let live = try await world.live()
            let kept = live?.id == first.id
            #expect(kept == (fault == .discard || fault == .programStore), "the old workout goes only with its discard")
            #expect(live == nil || kept || fault == .startAnswerLost)
            let title = "Couldn't start the new workout / "
            if !readable {
                #expect(words(rig) == title + "Try again.", "live: \(live != nil), kept: \(kept)")
            } else if fault == .startAnswerLost {
                #expect(rig.phase == .cover, "\(rig.phase)")
            } else {
                #expect(words(rig) == title +
                    (kept ? "Your workout in progress was kept." : "Your workout in progress was discarded."))
            }
        }
    }

    /// What a replacement can be refused for, with a reason the lifter can act on.
    nonisolated enum Refusal: String, Sendable, CaseIterable {
        case emptied, deleted, blockEnded

        var line: String {
            switch self {
            case .emptied: "This day has no exercises yet."
            case .deleted: "This day is no longer in your program."
            case .blockEnded: "Your program's block has ended."
            }
        }
    }

    /// The dialog up for day 1 over day 0's workout, then the refusal made true.
    func refused(_ refusal: Refusal, in world: World) async throws -> (rig: AdversarialRig, asked: WorkoutSource) {
        let rig = AdversarialRig()
        let asked = world.source(day: 1, week: refusal == .blockEnded ? world.program.weeks.count : 0)
        await rig.start(asked)
        #expect(rig.phase == .conflict(asked), "\(rig.phase)")
        if refusal != .blockEnded {
            _ = try await world.stores.programs.update(world.program.id) { program in
                var changed = program
                if refusal == .emptied {
                    changed.days[1].slots = []
                } else {
                    let gone = changed.days.remove(at: 1).id
                    for index in changed.weeks.indices {
                        changed.weeks[index].schedule = changed.weeks[index].schedule.filter { $0.value != gone }
                    }
                }
                return changed
            }
        }
        await world.session.clearCalls()
        return (rig, asked)
    }

    @Test("Criterion 15: a replacement refused for a reason says it, and discards nothing", arguments: Refusal.allCases)
    func refusedReplacement_saysWhy(refusal: Refusal) async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let (rig, asked) = try await refused(refusal, in: world)
            await rig.answer(.replaceLive(asked))
            #expect(words(rig) == "Couldn't start this workout / " + refusal.line)
            #expect(await world.session.count(.discard) == 0)
            #expect(try await unchanged(world.live(), first))
            await rig.answer(.dismissFailure)
            await rig.resume()
            #expect(rig.shown?.id == first.id, "the workout that was running is still reachable")
        }
    }

    /// Finding F10-S4-7. The reason is known from the error alone: every one of these refusals is thrown
    /// before the use case discards anything. The launcher says it only when its second read of the session
    /// succeeds and shows the old workout.
    @Test(
        "Criterion 15: the reason is said also when the session cannot be read afterwards",
        arguments: Refusal.allCases
    )
    func refusedReplacement_sessionUnreadable_stillSaysWhy(refusal: Refusal) async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let (rig, asked) = try await refused(refusal, in: world)
            await world.session.fail(.current, times: 9, skipping: refusal == .blockEnded ? 1 : 0)
            await rig.answer(.replaceLive(asked))
            await world.session.heal()
            #expect(words(rig).hasSuffix(refusal.line), "\(words(rig))")
            #expect(try await unchanged(world.live(), first))
        }
    }

    /// Finding F10-S4-8. The workout that was running was **saved** by another hand while the dialog showed;
    /// the replacement is then refused for a reason. The lifter is told it was discarded, and not the reason.
    @Test("A workout finished elsewhere under the dialog is never called discarded", arguments: Refusal.allCases)
    func refusedReplacement_afterFinishElsewhere_doesNotSayDiscarded(refusal: Refusal) async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let (rig, asked) = try await refused(refusal, in: world)
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(60))
            await rig.answer(.replaceLive(asked))
            let saved = try await world.stores.workouts.workout(id: first.id)
            #expect(saved?.phase == .finished, "it is in history")
            #expect(!words(rig).contains("discarded"), "\(words(rig))")
            #expect(words(rig).hasSuffix(refusal.line), "\(words(rig))")
        }
    }

    @Test("A resume whose first read fails opens the workout when the second read finds it")
    func resume_oneFailedRead_opensTheWorkout() async throws {
        try await World.run(.host) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await world.session.fail(.current)
            await rig.resume()
            #expect(rig.phase == .cover, "\(rig.phase)")
            #expect(rig.shown?.id == first.id)
        }
    }
}
