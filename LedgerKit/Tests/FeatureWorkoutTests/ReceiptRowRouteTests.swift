import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3, N18 (Pete's question 2, A): a row of the receipt leads to its exercise's history. The presentation gives
/// each row its exercise's action; the store closes the cover as saved with the exercise's route, once, and only
/// from the receipt. The app's mapping is `LibraryRouteMappingTests`' in LedgerAppKitTests; the rows as buttons
/// are `ReceiptTests`'.
@MainActor
@Suite("Receipt rows", .tags(.feature), .timeLimit(.minutes(1)))
struct ReceiptRowRouteTests {
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    @Test("Each row's action opens its own exercise's history, in the rows' order")
    func rowActions_areTheExercisesInOrder() throws {
        let workout = try Save.logged(2)
        let model = WorkoutPresentation.receipt(
            workout,
            records: [],
            locale: Fixtures.locale,
            calendar: Fixtures.calendar
        )
        #expect(model.page.rows.count == workout.exercises.count)
        #expect(model.rowActions == workout.exercises.map { .openExercise($0.exerciseID) })
        #expect(model.page.rows.map(\.name) == workout.exercises.map(\.name))
    }

    @Test("A row of the receipt closes the cover with that exercise's history; a second tap changes nothing")
    func row_onTheReceipt_closesWithTheExercise() async throws {
        let running = try Save.logged(2)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await WorkoutStoreReceiptTests.following(scene)
        defer { task.cancel() }
        store.send(.finish)
        store.send(.save)
        await store.save()
        let receipt = try #require(store.receipt)
        let bench = running.exercises[0].exerciseID
        #expect(receipt.rowActions.first == .openExercise(bench))
        store.send(.openExercise(bench))
        #expect(store.exit == .route(.exercise(bench)))
        store.send(.openExercise(running.exercises[1].exerciseID))
        store.send(.done)
        #expect(store.exit == .route(.exercise(bench)), "the cover closes once")
    }

    @Test("Before the receipt a row's action does nothing: the live workout stays")
    func row_beforeTheReceipt_doesNothing() async throws {
        let running = try Save.logged(2)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await WorkoutStoreReceiptTests.following(scene)
        defer { task.cancel() }
        store.send(.openExercise(running.exercises[0].exerciseID))
        #expect(store.exit == nil)
        #expect(store.receipt == nil)
        #expect(store.shown?.id == running.id)
    }
}
