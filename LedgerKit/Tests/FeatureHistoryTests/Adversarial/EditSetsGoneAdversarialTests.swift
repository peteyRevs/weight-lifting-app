import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S3 adversarial (G2): a workout deleted under the sheet, the sheet's store and the detail's together over one
/// store, as `WorkoutDetailRoot` joins them, from the delete to the route: a nil that must wait, shown by a later value
/// from the same stream and not by a yield, then each way the sheet comes down.
@MainActor
@Suite("Adversarial F13 S3 · a workout deleted under the sheet", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct EditSetsGoneAdversarialTests {
    private typealias Scene = EditAdversarialScene
    static let newest = EditAdversarialScene.newest

    private static func raised(_ workout: WorkoutState, to pounds: Decimal) -> WorkoutState {
        var raised = workout
        raised.exercises[0].sets[0].weight = .pounds(pounds)
        return raised
    }

    /// What the root does with a waiting route: hands it over, and it is gone.
    private static func deliver(_ detail: WorkoutDetailStore) -> [HistoryRoute] {
        var routes: [HistoryRoute] = []
        detail.deliverRoute { routes.append($0) }
        return routes
    }

    // MARK: - A nil that waits, shown by a later value

    @Test("N12. A nil under the sheet is processed and asks for nothing: a later value of the same stream shows it was")
    func nilUnderTheSheet_isProcessed_andWaits() async {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        scene.workouts.observation.yield(scene.recorded(Self.newest))
        await eventually {
            if case .loaded = scene.detail.state {
                true
            } else {
                false
            }
        }
        scene.detail.edit()
        #expect(scene.detail.editing != nil)
        // In order: the nil, then a value whose receipt differs. Seeing the second means the first went through.
        scene.workouts.observation.yield(nil)
        scene.workouts.observation.yield(scene.recorded(Self.raised(Self.newest, to: 777)))
        await eventually {
            guard case let .loaded(model) = scene.detail.state else {
                return false
            }
            return model.receipt.rows.first?.chips.first?.contains("777") == true
        }
        #expect(scene.detail.pendingRoute == nil, "the nil asked for a close while the sheet was up")
    }

    @Test("N12. The control: with no sheet up, the same nil closes at once")
    func nilWithoutASheet_closes() async {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        scene.workouts.observation.yield(scene.recorded(Self.newest))
        await eventually {
            if case .loaded = scene.detail.state {
                true
            } else {
                false
            }
        }
        scene.workouts.observation.yield(nil)
        await eventually { scene.detail.state == .gone }
        #expect(scene.detail.pendingRoute?.route == .closeWorkout(Self.newest.id))
    }

    // MARK: - The gone flow, end to end

    @Test("N12. Deleted under the sheet: Save says so, OK closes both, and the app gets one close, with nothing stored")
    func goneFlow_okClosesBoth() async throws {
        let scene = Scene()
        let run = scene.run()
        defer { run.cancel() }
        await eventually {
            if case .loaded = scene.detail.state {
                true
            } else {
                false
            }
        }
        scene.detail.edit()
        let request = try #require(scene.detail.editing)
        let sheet = scene.sheet(request)
        let set = try #require(request.workout.exercises.first?.sets.first)
        sheet.send(.step(set.id, .weight, .upward))
        try await scene.workouts.delete(id: Self.newest.id)
        // The detail hears the delete, and waits.
        var heard = scene.memory.workouts.observeWorkout(id: Self.newest.id).makeAsyncIterator()
        _ = await heard.next()
        #expect(scene.detail.pendingRoute == nil)
        sheet.send(.save)
        await sheet.save()
        #expect(sheet.phase == .workoutGone)
        #expect(sheet.model.workoutGone != nil)
        #expect(sheet.canClose, "the alert's OK can close")
        sheet.send(.step(set.id, .reps, .upward))
        sheet.send(.save)
        #expect(sheet.phase == .workoutGone, "nothing moves behind the alert")
        scene.detail.editClosed(workoutGone: true)
        #expect(scene.detail.editing == nil)
        #expect(scene.detail.state == .gone)
        #expect(Self.deliver(scene.detail) == [.closeWorkout(Self.newest.id)])
        #expect(Self.deliver(scene.detail).isEmpty, "one close")
        #expect(try await scene.memory.workouts.workout(id: Self.newest.id) == nil, "the save brought nothing back")
    }

    @Test("N12. Deleted under the sheet, then Cancel or a swipe, with nothing saved: the detail still closes")
    func goneFlow_cancelClosesTheDetail() async {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        scene.workouts.observation.yield(scene.recorded(Self.newest))
        await eventually {
            if case .loaded = scene.detail.state {
                true
            } else {
                false
            }
        }
        scene.detail.edit()
        scene.workouts.observation.yield(nil)
        // A settings value goes through `rebuild`, and the nil is on its way: wait for the close the sheet's end asks.
        await settlesAfterNil(scene)
        scene.detail.editClosed(workoutGone: false)
        #expect(scene.detail.state == .gone)
        #expect(Self.deliver(scene.detail) == [.closeWorkout(Self.newest.id)])
    }

    /// Lets a yielded nil reach the store: a later value proves it, then the nil is told again, as GRDB's would stand.
    private func settlesAfterNil(_ scene: Scene) async {
        scene.workouts.observation.yield(scene.recorded(Self.raised(Self.newest, to: 778)))
        await eventually {
            guard case let .loaded(model) = scene.detail.state else {
                return false
            }
            return model.receipt.rows.first?.chips.first?.contains("778") == true
        }
        scene.workouts.observation.yield(nil)
        // Nothing follows the nil to show it landed; the stream is FIFO and only the main actor runs it.
        for _ in 0 ..< 500 {
            await Task.yield()
        }
    }

    /// Info, F13-S3-8: a system `set(nil)` after OK would redraw the receipt over `.gone` until the nil lands, as
    /// `editClosed(false)` rebuilds. SwiftUI sends no `set` when the store itself cleared the item. Either way one
    /// close.
    @Test("A sheet that says gone, and a binding that then says nil, leave one close waiting")
    func goneFlow_bothSignals_leaveOneClose() async {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        scene.workouts.observation.yield(scene.recorded(Self.newest))
        await eventually {
            if case .loaded = scene.detail.state {
                true
            } else {
                false
            }
        }
        scene.detail.edit()
        scene.detail.editClosed(workoutGone: true)
        scene.detail.editClosed(workoutGone: false)
        #expect(Self.deliver(scene.detail) == [.closeWorkout(Self.newest.id)])
        #expect(Self.deliver(scene.detail).isEmpty)
    }
}
