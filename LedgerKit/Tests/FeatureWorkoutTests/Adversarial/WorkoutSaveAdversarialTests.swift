import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 8, 9 and 11: no logged set is lost. A seeded storm of the page's taps (logs,
/// un-logs, steppers, "+30s", "Skip rest") with every call held, the page behind the answers and the date
/// moving, then "Finish" and "Save workout" at a seeded point with taps still waiting, and more taps after
/// it. What the session was asked, and the workout it ended with, are those of the same taps made one at a
/// time, each applied and shown before the next, and then saved.
@MainActor
@Suite("Workout save (adversarial)", .tags(.feature), .timeLimit(.minutes(2)))
struct WorkoutSaveAdversarialTests {
    typealias Rest = WorkoutRestAdversarialTests

    /// What one seed does: the taps before "Save workout", the instant of each, the instant of the save,
    /// and the taps a lifter tries after it.
    struct Script {
        var taps: [WorkoutEdit] = []
        var instants: [Date] = []
        var savedAt = Fixtures.now
        var late: [WorkoutEdit] = []
    }

    static func script(seed: UInt64) -> Script {
        var generator = SplitMix64(seed: seed ^ 0x5A7E)
        let all = Rest.tapsWithRest(seed: seed, in: EventBuilders.seedSession(), count: 48)
        let cut = Int.random(in: 3 ... 40, using: &generator)
        var script = Script(taps: Array(all[..<cut]), late: Array(all[cut...].prefix(5)))
        var moment = Fixtures.now
        for _ in script.taps {
            // One tap in three comes within a second of the one before (the un-log guard's second).
            let isQuick = Int.random(in: 0 ..< 3, using: &generator) == 0
            moment += Double.random(in: isQuick ? 0.05 ... 0.95 : 1 ... 25, using: &generator)
            script.instants.append(moment)
        }
        script.savedAt = moment + Double.random(in: 0.1 ... 40, using: &generator)
        return script
    }

    /// What a run came to.
    struct Outcome {
        var reached: [SaveSession.Reached] = []
        var ended: WorkoutState?
        var live: WorkoutState?
        var exit: WorkoutExit?
        var dialog: WorkoutDialog?
        var isSaving = false
        var finishesAsked: [Date] = []
        /// The taps that had not been applied when "Save workout" was tapped; nil when it never answered.
        var waitingAtTheSave: Int?

        @MainActor
        init(_ cover: SaveCover, waitingAtTheSave: Int? = nil) async {
            reached = await cover.session.reached
            ended = await cover.session.ended
            live = await cover.session.current()
            finishesAsked = await cover.session.finishesAsked
            exit = cover.store.exit
            dialog = cover.store.dialog
            isSaving = cover.store.isSaving
            self.waitingAtTheSave = waitingAtTheSave
        }
    }
}

extension WorkoutSaveAdversarialTests {
    /// Each tap made at its instant, applied and shown before the next; then "Finish" and "Save workout".
    static func calm(_ script: Script) async -> Outcome {
        let cover = await SaveCover()
        for (tap, instant) in zip(script.taps, script.instants) {
            cover.clock.setValue(instant)
            cover.tap(tap)
            await cover.until("the tap to be applied") { cover.store.queue.isEmpty && !cover.store.isDraining }
            let truth = await cover.session.current()
            await cover.until("the page to show it") { cover.store.shown == truth }
        }
        cover.clock.setValue(script.savedAt)
        cover.send(.finish, .save)
        await cover.until("the save to end") { cover.store.exit != nil || !cover.store.isSaving }
        await cover.rest()
        let outcome = await Outcome(cover)
        await cover.close()
        return outcome
    }

    /// The same taps in bursts at the same instants, every call held and the page behind; "Finish" with
    /// taps still waiting; "Save workout" as soon as the button answers; then the late taps and every
    /// other control, which must change nothing; then the calls are let on, a few at a time, as time goes by.
    static func storm(_ script: Script, seed: UInt64) async -> Outcome {
        let cover = await SaveCover()
        await cover.session.holdEveryApply()
        await cover.session.keepStreamsBehind()
        var generator = SplitMix64(seed: seed ^ 0xF1A5)
        var next = 0
        while next < script.taps.count {
            for _ in 0 ..< Int.random(in: 1 ... 4, using: &generator) where next < script.taps.count {
                let instant = script.instants[next]
                cover.clock.setValue(instant)
                cover.tap(script.taps[next])
                next += 1
            }
            // Fewer calls are let on than taps were made, so the queue grows towards the save.
            let limit = next < script.taps.count ? script.instants[next] : script.savedAt
            for _ in 0 ..< Int.random(in: 0 ... 2, using: &generator) {
                await letOn(cover, upTo: limit, &generator)
            }
        }
        return await save(cover, script, &generator)
    }

    /// "Finish" with taps still waiting, "Save workout" as soon as it answers, then everything a lifter can
    /// still reach while it saves, as the calls are let on and time goes by.
    private static func save(_ cover: SaveCover, _ script: Script, _ generator: inout SplitMix64) async -> Outcome {
        cover.clock.setValue(script.savedAt)
        cover.send(.finish)
        // A lifter can tap "Save workout" only once it answers: with no set shown as logged it does not.
        for _ in 0 ..< 400 where cover.store.finishSheet?.canSave != true && isBusy(cover) {
            await letOn(cover, upTo: script.savedAt, &generator)
        }
        await cover.rest()
        guard cover.store.finishSheet?.canSave == true else {
            let outcome = await Outcome(cover)
            await cover.close()
            return outcome
        }
        let waiting = cover.store.queue.count
        cover.clock.setValue(script.savedAt)
        cover.send(.save)
        cover.clock.withValue { $0 += 3 }
        for tap in script.late {
            cover.tap(tap)
        }
        cover.send(.save, .keepLifting, .discard, .retrySave, .dismissFailure, .finish, .minimize)
        for _ in 0 ..< 2000 where cover.store.exit == nil && cover.store.isSaving {
            let step = Double.random(in: 0 ... 20, using: &generator)
            cover.clock.withValue { $0 += step }
            await cover.session.release()
            await cover.session.deliver(Int.random(in: 0 ... 2, using: &generator))
            await cover.rest()
        }
        await cover.settle()
        let outcome = await Outcome(cover, waitingAtTheSave: waiting)
        await cover.close()
        return outcome
    }

    private static func isBusy(_ cover: SaveCover) -> Bool {
        !cover.store.queue.isEmpty || cover.store.isDraining || cover.session.waiting.value > 0
            || cover.store.ahead != nil
    }

    /// One call is let on and up to two updates reach the page, while the date moves towards `limit`.
    private static func letOn(_ cover: SaveCover, upTo limit: Date, _ generator: inout SplitMix64) async {
        let share = Double.random(in: 0 ... 0.9, using: &generator)
        cover.clock.withValue { $0 += limit.timeIntervalSince($0) * share }
        await cover.session.release()
        await cover.session.deliver(Int.random(in: 0 ... 2, using: &generator))
        await cover.rest()
    }

    @Test(
        "Taps in a storm, then Save workout with taps still waiting: the saved workout is the calm one's",
        arguments: RestSeeds.all
    )
    func storm_savesWhatTheCalmRunSaves(seed: UInt64) async {
        let script = Self.script(seed: seed)
        let calm = await Self.calm(script)
        let storm = await Self.storm(script, seed: seed)
        let firstDifference = zip(calm.reached, storm.reached).enumerated()
            .first { $0.element.0 != $0.element.1 }?.offset
        #expect(firstDifference == nil, "seed \(seed): the calls differ from number \(firstDifference ?? -1)")
        #expect(calm.reached.count == storm.reached.count, "seed \(seed)")
        let isSameWorkout = unchanged(storm.ended ?? storm.live, calm.ended ?? calm.live)
        #expect(isSameWorkout, "seed \(seed)")
        #expect(storm.exit == calm.exit, "seed \(seed)")
        #expect(storm.dialog == calm.dialog, "seed \(seed)")
        #expect(!storm.isSaving || storm.exit != nil, "seed \(seed)")

        // The calm run against the criteria, not against the store: saved exactly when a set is logged once
        // every tap is applied, ended at the tap on "Save workout", once.
        let logged = (calm.ended ?? calm.live)?.doneSets ?? 0
        if logged > 0 {
            #expect(calm.reached.last == .finished(script.savedAt), "seed \(seed)")
            #expect(calm.ended?.phase == .finished, "seed \(seed)")
            #expect(calm.exit == calm.ended.map { .route(.saved($0.id)) }, "seed \(seed)")
            #expect(storm.finishesAsked == [script.savedAt], "seed \(seed): asked \(storm.finishesAsked.count) times")
        } else {
            #expect(calm.ended == nil, "seed \(seed): a workout with no set logged was ended")
            #expect(storm.finishesAsked == [], "seed \(seed)")
            #expect(storm.dialog == .finish, "seed \(seed): the sheet stays, with Save workout dimmed")
            #expect(storm.exit == nil, "seed \(seed)")
        }
    }

    @Test("The storm's saves are not vacuous: taps wait at the save, sets are logged, and some saves find none")
    func storm_isNotVacuous() async {
        var (saved, waiting, withdrawn, sets, changes) = (0, 0, 0, 0, 0)
        for seed in RestSeeds.all.prefix(40) {
            let storm = await Self.storm(Self.script(seed: seed), seed: seed)
            saved += storm.ended?.phase == .finished ? 1 : 0
            waiting += storm.waitingAtTheSave ?? 0
            withdrawn += storm.waitingAtTheSave != nil && storm.ended == nil ? 1 : 0
            sets += storm.ended?.doneSets ?? 0
            changes += storm.reached.count
        }
        print("save storm, first 40 seeds: saved \(saved), taps waiting at the save \(waiting),"
            + " saves that found no set \(withdrawn), sets saved \(sets), calls \(changes)")
        #expect(saved >= 20)
        #expect(waiting >= 60)
        #expect(sets >= 40)
    }
}
