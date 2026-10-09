@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5 adversarial round 1 (G2): the store over sources driven by hand (`ScriptedScene`). Streams that
/// speak in every order, say the same thing twice and end. Nothing here waits for time. (The task cancelled
/// and started again, and the routes, are `TodayStoreRestartAdversarialTests`.)
@MainActor
@Suite("Adversarial: TodayStore over scripted sources", .tags(.feature), .timeLimit(.minutes(2)))
struct TodayStoreStreamsAdversarialTests {
    /// Every order of five things.
    static func permutations(_ items: [String]) -> [[String]] {
        guard items.count > 1 else {
            return [items]
        }
        return items.indices.flatMap { index -> [[String]] in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
    }

    // MARK: Criterion 1: the first model waits for all five, in any order

    @Test("In each of the 120 orders the sources can first speak, nothing is read or shown before the fifth")
    func everyOrder_showsNothingBeforeTheFifthSource() async throws {
        var failures: [String] = []
        for order in Self.permutations(ScriptedScene.sources) {
            let scene = ScriptedScene()
            let task = await scene.running()
            for name in order.dropLast() {
                try scene.speak(name)
            }
            await drain(turns: 30)
            if scene.store.phase != "loading" || scene.workouts.reads != 0 {
                failures.append("\(order): \(scene.store.phase) after four, \(scene.workouts.reads) reads")
            }
            try scene.speak(order[4])
            let isLoaded = await settles { scene.store.model != nil }
            let title = scene.store.model?.card.upNext?.title
            if !isLoaded || title != "Lower A — Squat focus" || scene.workouts.reads != 1 {
                failures.append("\(order): \(scene.store.phase) \(title ?? "-"), \(scene.workouts.reads) reads")
            }
            task.cancel()
            await task.value
        }
        #expect(failures == [])
    }

    // MARK: The same value twice

    @Test("A source that says again what it said publishes nothing", arguments: ScriptedScene.sources)
    func sameValueTwice_publishesNothing(_ name: String) async throws {
        let scene = ScriptedScene()
        let task = await scene.running()
        try scene.speakAll()
        let isLoaded = await settles { scene.store.model != nil }
        #expect(isLoaded)
        await drain(turns: 30)
        let publications = StatePublications(scene.store)
        let reads = scene.workouts.reads
        for _ in 0 ..< 3 {
            try scene.speak(name)
        }
        // The sources the reads depend on read again; that is how the three were seen to be taken in.
        if ["program", "settings", "recent"].contains(name) {
            let hasReadAgain = await comes { scene.workouts.reads > reads }
            #expect(hasReadAgain, "\(name) makes the reads stale")
        }
        await drain(turns: 60)
        #expect(publications.changes == 0, "\(publications.phases)")
        #expect(scene.store.phase == "loaded")
        let readsMade = scene.workouts.reads - reads
        #expect(readsMade <= 3, "at most one read per value: \(readsMade)")
        // An update without a live workout reads again by the store's rule (it may be the one that ended a
        // workout); the exercises are no reason to.
        if name == "exercises" {
            #expect(readsMade == 0, "\(name) is no reason to read the week again")
        }
        task.cancel()
    }

    // MARK: Deviation 5: a stream that ends

    @Test(
        "A store's observation that ends over a loaded model shows the failure; only a new run recovers, unseen",
        arguments: ["program", "settings", "exercises", "recent"]
    )
    func storeStreamEnds_overALoadedModel_failsUntilANewRun(_ name: String) async throws {
        let scene = ScriptedScene()
        let first = await scene.running()
        try scene.speakAll()
        #expect(await settles { scene.store.model != nil })
        switch name {
        case "program": scene.programs.finish()
        case "settings": scene.settings.finish()
        case "exercises": scene.exercises.finish()
        default: scene.recent.finish()
        }
        #expect(await settles { scene.store.isFailed }, "\(name) ended: \(scene.store.phase)")
        guard case let .failed(error) = scene.store.state else {
            return
        }
        #expect(error as? TodayStoreError == .observationEnded)

        // The other sources still speak: the source that ended is gone, so the day stays unknown.
        scene.session.yield(WorkoutSessionUpdate(state: nil))
        scene.recent.yield([])
        await drain(turns: 60)
        #expect(scene.store.phase == "failed")

        // A new run listens again: it goes from the failure to the model, with no loading between.
        let publications = StatePublications(scene.store)
        first.cancel()
        let second = await scene.running()
        #expect(await settles { scene.store.model != nil })
        await drain(turns: 30)
        #expect(publications.phases == ["failed", "loaded"])
        second.cancel()
    }

    /// As built, and a question for Pete (notes, question Q1; the implementer's open question 2). Criterion 3
    /// keeps the off-schedule sheet's list through every change, because `TodayScreen` closes the sheet when
    /// the state stops offering the list; deviation 5 shows a failed read over a loaded model, which takes
    /// the list away just the same. So one read that fails while the sheet is open closes it under the
    /// lifter's finger. The failure does recover with the next change of any source, the exercises included.
    @Test("As built: a read that fails over the rest day takes the sheet's list away; any later change brings it back")
    func readFails_overTheRestDay_takesTheListAway_untilTheNextChange() async throws {
        let scene = ScriptedScene()
        scene.clock.value = Fixtures.date(2026, 9, 17, hour: 5, minute: 20)
        let task = await scene.running()
        try scene.speakAll()
        #expect(await settles { scene.store.model != nil })
        let days = try #require(scene.store.model?.card.restDay?.offSchedule.days)
        #expect(days.count == 4)

        scene.workouts.isFailing = true
        scene.recent.yield([])
        #expect(await settles { scene.store.isFailed })
        #expect(scene.store.model == nil, "the list the sheet draws is gone with the model")

        // The exercises are no reason to read again, but nothing is known, so the read is made: it recovers.
        scene.workouts.isFailing = false
        try scene.exercises.yield(ExerciseCatalog.seed())
        #expect(await settles { scene.store.model != nil })
        let isSameList = scene.store.model?.card.restDay?.offSchedule.days == days
        #expect(isSameList)
        task.cancel()
    }

    @Test("A session whose updates end over a loaded model is no failure: the day stays, and still follows the stores")
    func sessionStreamEnds_overALoadedModel_staysLoaded() async throws {
        let scene = ScriptedScene()
        let task = await scene.running()
        try scene.speakAll()
        #expect(await settles { scene.store.model != nil })
        scene.session.finish()
        await drain(turns: 60)
        #expect(scene.store.phase == "loaded")
        var program = try TodayFixtures.program()
        program.days[TodayFixtures.DayIndex.lowerA].name = "Legs"
        scene.programs.yield(program)
        #expect(await settles { scene.store.model?.card.upNext?.title == "Legs" })
        task.cancel()
    }

    /// As built, and a question for the orchestrator (notes, question Q3): a session whose updates end while
    /// its workout is live leaves "Resume" on the card until a new run. Deviation 5 reads an ended session as
    /// "nothing live", which holds for a stream that ended before its first update (the key's stub) and not
    /// for this one. The app's host never ends its stream, so no lifter meets it today; this pins what
    /// happens so that a change of the rule is seen.
    @Test("As built: a session whose updates end while a workout is live keeps Resume until a new run")
    func sessionStreamEnds_whileLive_keepsResume() async throws {
        let scene = ScriptedScene()
        let task = await scene.running()
        try scene.speakAll()
        #expect(await settles { scene.store.model != nil })
        try scene.session.yield(WorkoutSessionUpdate(state: TodayScene.liveLowerA()))
        #expect(await settles { scene.store.model?.card.upNext?.action.action.route == .resumeWorkout })
        scene.session.finish()
        await drain(turns: 60)
        #expect(scene.store.phase == "loaded")
        #expect(scene.store.model?.card.upNext?.action.action.route == .resumeWorkout)
        task.cancel()
    }
}
