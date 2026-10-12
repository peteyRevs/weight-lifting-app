import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// G2, F10 S6 round 2, ruling 16: a tick redraws the rest panel and nothing else. By observation on the
/// store (what the root's body, the header, the page and the dialogs read does not change at a tick, at a
/// rest's end or after time away), and by the module's sources (one view reads the store's panel; the
/// moment is read in the store alone).
extension WorkoutRestAdversarialTests {
    /// Counts the changes of what `read` reads, until its task is cancelled (the implementer's helper of fix round 1
    /// for
    /// `eachSecond_oneChange_thePageUntouched`, moved here from that test's file for its length).
    static func counting(
        _ read: @escaping @MainActor @Sendable () -> some Equatable & Sendable
    ) -> (count: LockIsolated<Int>, task: Task<Void, Never>) {
        let count = LockIsolated(0)
        let task = Task {
            for await _ in Observations({ read() }) {
                count.withValue { $0 += 1 }
            }
        }
        return (count, task)
    }

    /// Whether anything `read` reads changes while `body` runs (one change is enough to tell).
    static func changes(
        of read: @MainActor () -> Void,
        while body: @MainActor () async -> Void
    ) async -> Bool {
        let fired = LockIsolated(false)
        withObservationTracking(read) { fired.setValue(true) }
        await body()
        return fired.value
    }

    @Test(
        "Ten seconds of a rest, its end, and 40 s away change nothing the root, the header, the page or a dialog read"
    )
    func tick_changesNothingTheRootReads() async throws {
        let (cover, rows) = try await Self.resting()
        let store = cover.store
        let everythingButThePanel: @MainActor () -> Void = {
            _ = store.model
            _ = store.dialog
            _ = store.discardAttempt
            _ = store.shownRest
            _ = store.exit
            _ = store.isShowingWorkout
            _ = store.selection
        }
        #expect(await Self.changes(of: everythingButThePanel) { await cover.run(10) } == false)
        #expect(await Self.changes(of: { _ = store.restPanel }, while: { await cover.run(1) }), "the control")
        #expect(await Self.changes(of: everythingButThePanel) { await cover.suspend(40) } == false)
        #expect(cover.panel?.clock == ClockText.remaining(.seconds(150 - 51 - 1)), "right at once after 40 s away")
        #expect(
            await Self.changes(of: everythingButThePanel) { await cover.run(120) } == false,
            "through the rest's end"
        )
        #expect(cover.panel?.status == "Rest over")
        // The control for the first reader: a tap of the page does change what it reads.
        let didChange = await Self.changes(of: everythingButThePanel) {
            await cover.tap(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment))
        }
        #expect(didChange)
        await cover.close()
    }

    @Test("While Minimize waits for a tap, the store's panel is disabled with the page, and the cover then closes")
    func panel_isDisabledWhileTheCoverCloses() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: rows[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        #expect(bench.store.restPanel?.isEnabled == true)
        await bench.session.holdEveryApply()
        bench.store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment)))
        bench.store.send(.minimize)
        #expect(bench.store.exit == nil, "Minimize waits")
        #expect(bench.store.restPanel?.isEnabled == false)
        #expect(bench.store.model.page?.isEnabled == false)
        bench.store.send(.edit(.skipRest))
        #expect(bench.store.queue.count == 1, "and a tap on the panel now is not taken")
        await bench.session.holdEveryApply(false)
        await Self.drainSlowly(bench)
        #expect(bench.store.exit == .route(.minimized))
        bench.following.cancel()
    }

    @Test("In the module's sources the panel is read from the store in one place, and the moment in the store alone")
    func sources_onlyThePanelReadsTheMoment() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureWorkout")
        func uses(of spelling: String) -> [String] {
            sources.sorted { $0.key < $1.key }.flatMap { path, text in
                SwiftSource(text).lines(ofCode: spelling).map { _ in (path as NSString).lastPathComponent }
            }
        }
        #expect(uses(of: "store.restPanel") == ["WorkoutRoot.swift"], "one view reads the store's panel")
        // (`WorkoutTimeline.fixed(at moment:)` is a parameter of that name, not the store's.)
        let readers = Set(uses(of: "moment")).subtracting(["WorkoutTimeline.swift"])
        #expect(readers == ["WorkoutStore.swift", "WorkoutStore+Rest.swift", "WorkoutStore+Pump.swift"])
        #expect(uses(of: "moment").count { $0 == "WorkoutStore.swift" } == 1, "declared there, and read nowhere in it")
    }
}
