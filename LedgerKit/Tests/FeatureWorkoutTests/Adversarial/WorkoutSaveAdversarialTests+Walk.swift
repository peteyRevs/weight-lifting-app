import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 8, 13 to 18: a seeded walk of a cover that can save.
extension WorkoutSaveAdversarialTests {
    /// What a walk did and what it met.
    struct Walk {
        var trail: [String] = []
        var fault: String?
        var saves = 0
        var retries = 0
        var restarts = 0
        var exit: WorkoutExit?
        /// The cover closed as saved on a workout that another hand discarded, unheard: as built, and
        /// pinned by `discardedElsewhere_unheard_closesAsSaved_asBuilt` (the notes' input for F17).
        var misreportedADiscard = false

        /// Counts what the step did, and keeps the end a new save was tapped at.
        @MainActor
        mutating func note(_ name: String, _ before: Before, _ cover: SaveCover, _ ends: inout Set<Date>) {
            trail.append(name)
            restarts += name == "restart" ? 1 : 0
            guard cover.store.saveAttempt != before.attempt else {
                return
            }
            guard before.dialog == .saveFailed else {
                saves += 1
                ends.insert(cover.clock.value)
                return
            }
            retries += 1
            if cover.store.pendingSave?.endedAt != before.save?.endedAt {
                fault = "Try again asks for another end than the first tap's"
            }
        }
    }

    /// What a step of the walk found before it acted.
    struct Before {
        let attempt: Int
        let save: PendingSave?
        let dialog: WorkoutDialog?

        @MainActor
        init(_ store: WorkoutStore) {
            attempt = store.saveAttempt
            save = store.pendingSave
            dialog = store.dialog
        }
    }

    /// Seeded steps of everything a lifter, SwiftUI, the session and another hand can do to a cover that
    /// can save: taps, the sheet's three controls, the alert's two, the tasks starting again, calls held and
    /// let on, updates kept back, a finish that fails, an end from elsewhere. After each step, and at rest
    /// at the end, the cover is held to `SaveCover.fault()` and to the ends its taps asked for.
    static func walk(seed: UInt64, steps: Int = 90) async -> Walk {
        let cover = await SaveCover()
        var generator = SplitMix64(seed: seed ^ 0x0CE)
        let edits = Rest.tapsWithRest(seed: seed, in: cover.running, count: steps)
        var walk = Walk()
        var ends: Set<Date> = []
        cover.tap(.log(exerciseIndex: 1, setID: cover.set(1, 0)))
        await cover.until("the first set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        // Up to three finishes fail first, and in half the walks the ends, or the changes, start held.
        let failures = Int.random(in: 0 ... 3, using: &generator)
        await cover.session.failFinish(with: Array(repeating: SaveSession.Refused(), count: failures))
        await cover.session.holdEveryEnd(Bool.random(using: &generator))
        await cover.session.holdEveryApply(Bool.random(using: &generator))
        for step in 0 ..< steps where walk.fault == nil && cover.store.exit == nil {
            let passed = Double.random(in: 0 ... 12, using: &generator)
            cover.clock.withValue { $0 += passed }
            let before = Before(cover.store)
            let name = await act(on: cover, edits[step], &generator)
            walk.note(name, before, cover, &ends)
            await cover.rest()
            let asked = await cover.session.finishesAsked
            if !Set(asked).isSubset(of: ends) {
                walk.fault = "a finish was asked for an end no tap on Save workout gave"
            } else if cover.exits.count > 1 {
                walk.fault = "the cover closed twice: \(cover.exits)"
            } else if cover.store.isSaving, cover.store.isDiscarding {
                walk.fault = "saving and discarding at once"
            }
        }
        await cover.settle()
        let atRest = await cover.fault()
        walk.fault = walk.fault ?? atRest
        if walk.fault == SaveCover.savedButDiscarded, walk.trail.contains("endedElsewhere") {
            walk.misreportedADiscard = true
            walk.fault = nil
        }
        if walk.fault == nil, cover.store.exit == nil, cover.store.isSaving || cover.store.isDiscarding {
            walk.fault = "at rest, with nothing held, the cover still says it is ending the workout"
        }
        walk.exit = cover.store.exit
        await cover.close()
        return walk
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func act(on cover: SaveCover, _ edit: WorkoutEdit, _ generator: inout SplitMix64) async -> String {
        let session = cover.session
        switch Int.random(in: 0 ..< 40, using: &generator) {
        case 0 ..< 8:
            cover.tap(edit)
            return "tap"
        case 8 ..< 11:
            cover.send(.finish)
            return "finish"
        case 11 ..< 15:
            cover.send(.save)
            return "save"
        case 15:
            cover.send(.keepLifting)
            return "keep"
        case 16 ..< 18:
            // "Discard" is one tap and ends the walk: one walk in three meets it.
            guard Int.random(in: 0 ..< 8, using: &generator) == 0 else {
                cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, Int.random(in: 0 ..< 3, using: &generator))))
                return "log"
            }
            cover.send(.discard)
            return "discard"
        case 18 ..< 20:
            cover.send(.retrySave)
            return "retry"
        case 20:
            cover.send(.dismissFailure)
            return "dismiss"
        case 21 ..< 24:
            await cover.restartTasks(awaitingTheOld: false)
            return "restart"
        case 24 ..< 29:
            await session.release()
            return "release"
        case 29 ..< 32:
            await session.releaseEnd()
            return "releaseEnd"
        case 32 ..< 35:
            await session.deliver(Int.random(in: 1 ... 3, using: &generator))
            return "deliver"
        case 35:
            await session.failFinish(with: [SaveSession.Refused()])
            return "failNext"
        case 36:
            await session.holdEveryEnd(Bool.random(using: &generator))
            return "holdEnds"
        case 37:
            await session.holdEveryApply(Bool.random(using: &generator))
            return "holdApplies"
        case 38:
            let (isBehind, first) = (Bool.random(using: &generator), Bool.random(using: &generator))
            await session.keepStreamsBehind(isBehind, first: first)
            return "behind"
        default:
            let end: WorkoutEvent = Bool.random(using: &generator)
                ? .finished(endedAt: cover.clock.value) : .discarded(endedAt: cover.clock.value)
            guard Int.random(in: 0 ..< 6, using: &generator) == 0 else {
                return "nothing"
            }
            _ = try? await session.elsewhere(end)
            return "endedElsewhere"
        }
    }

    @Test(
        "A seeded walk of taps, saves, discards, restarts, held and failing calls: one end, and the cover says it",
        arguments: RestSeeds.all
    )
    func walk_endsOnce_andTheCoverSaysHow(seed: UInt64) async {
        let walk = await Self.walk(seed: seed)
        #expect(walk.fault == nil, "seed \(seed): \(walk.trail.joined(separator: " "))")
    }

    @Test("The walk is not vacuous: it saves, retries, restarts, and closes each way")
    func walk_isNotVacuous() async {
        var (saves, retries, restarts) = (0, 0, 0)
        var exits: [String: Int] = [:]
        for seed in RestSeeds.all.prefix(40) {
            let walk = await Self.walk(seed: seed)
            saves += walk.saves
            retries += walk.retries
            restarts += walk.restarts
            exits["\(walk.exit.map { "\($0)" } ?? "open")", default: 0] += 1
        }
        print("save walk, first 40 seeds: saves \(saves), retries \(retries), restarts \(restarts), \(exits)")
        #expect(saves >= 40)
        #expect(retries >= 15)
        #expect(restarts >= 60)
        #expect(exits.count >= 2)
    }
}
