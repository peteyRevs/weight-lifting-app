import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2 round 2, F10 S5 criterion 18: the one-second guard on an un-log, through the store with a clock the
/// test moves; and (the fix round's move of the pump to a file of its own) that no other file of the module
/// reaches into the members of the store that lost `private` for it.
@MainActor
@Suite("Workout undo guard (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutUndoGuardAdversarialTests {
    typealias Bench = PumpBench

    @Test("A second touch inside the second changes nothing at all; at one second the check un-logs, and moves nothing")
    func secondTouch_insideAndAfterTheSecond() async throws {
        let bench = try await Bench.make()
        let (first, fourth) = (bench.set(0, 0), bench.set(0, 3))
        bench.tap(.log(exerciseIndex: 0, setID: first), .select(exerciseIndex: 0, setID: fourth))
        await bench.store.drain()
        let logged = try #require(await bench.settled())
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: fourth)
        #expect(bench.store.selection == chosen)

        for inside in [0.0, 0.5, 0.999] {
            bench.clock.setValue(Fixtures.now.addingTimeInterval(inside))
            bench.tap(.unlog(exerciseIndex: 0, setID: first))
            await bench.store.drain()
            #expect(await bench.session.applied.count == 2, "\(inside) s: a guarded un-log sends nothing")
            let isUntouched = await unchanged(bench.session.current(), logged)
            #expect(isUntouched, "\(inside) s")
            #expect(bench.store.selection == chosen && bench.store.dialog == nil && bench.store.exit == nil)
        }
        // The taps behind a guarded un-log are not dropped with it: it is no refusal.
        bench.tap(.unlog(exerciseIndex: 0, setID: first), .stepReps(exerciseIndex: 0, setID: fourth, .increment))
        await bench.store.drain()
        #expect(await bench.session.applied.count == 3)

        bench.clock.setValue(Fixtures.now.addingTimeInterval(1))
        bench.tap(.unlog(exerciseIndex: 0, setID: first))
        await bench.store.drain()
        let truth = try #require(await bench.settled())
        #expect(await bench.session.applied.last == .setUnlogged(exerciseIndex: 0, setID: first))
        #expect(truth.doneSets == 0)
        #expect(truth.cursor == logged.cursor && truth.rest == logged.rest, "rule 22: un-logging moves nothing")
        #expect(bench.store.selection == chosen)
        bench.following.cancel()
    }

    @Test(
        "A set logged elsewhere is guarded by its own moment: just logged it is kept; by a clock ahead it is not",
        arguments: [(-0.3, false), (-0.999, false), (-1.0, true), (-90.0, true), (0.001, true), (5.0, true)]
    )
    func setLoggedElsewhere(doneAfter: TimeInterval, isUnlogged: Bool) async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        try await bench.session.elsewhere(.setLogged(
            exerciseIndex: 0, setID: first, weight: .pounds(300), reps: .one,
            doneAt: Fixtures.now.addingTimeInterval(doneAfter)
        ))
        await bench.settled()
        #expect(bench.store.model.page?.card?.rows.first?.check == .unlog(exerciseIndex: 0, setID: first))
        bench.tap(.unlog(exerciseIndex: 0, setID: first))
        await bench.store.drain()
        #expect(await bench.session.applied.count == (isUnlogged ? 1 : 0))
        #expect(await bench.session.current()?.doneSets == (isUnlogged ? 0 : 1))
        bench.following.cancel()
    }

    /// The members of `WorkoutStore` that are no longer `private` since the pump moved to
    /// `WorkoutStore+Pump.swift`, as another file would have to spell them to reach in.
    nonisolated static let storesOwn = [
        ".queue", ".queueEpoch", ".exitWhenDrained", ".isHearingTheSession", ".isDraining", ".wake", ".ahead",
        ".emptyQueue(", ".enqueue(", ".leave(", ".minimize()", ".isShowingWorkout", ".selection = ", ".dialog = ",
        "store.session", "store.uuid", "store.date", "store.logger"
    ]

    @Test("No file but the store's two reaches into what the store keeps for its pump, and no view names the store")
    func storesMembers_areUsedByTheStoreAlone() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureWorkout")
        #expect(sources.keys.contains { $0.hasSuffix("WorkoutStore+Pump.swift") }, "the pump's file was not found")
        var hits: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) where !file.contains("WorkoutStore") {
            let isView = file.contains("Views/") || [
                "WorkoutHeader",
                "WorkoutPage.swift",
                "WorkoutScreen",
                "ExerciseCard",
                "SetRowList",
                "RemainingList"
            ].contains { file.contains($0) }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                for token in Self.storesOwn where code.contains(token) {
                    hits.append("\(file):\(number + 1): \(token)")
                }
                if isView, code.contains("WorkoutStore") {
                    hits.append("\(file):\(number + 1): a view names the store")
                }
            }
        }
        #expect(hits == [])
    }
}
