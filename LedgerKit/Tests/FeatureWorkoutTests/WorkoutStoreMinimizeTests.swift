@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criterion 14: "Minimize" and the taps made before it. The workout goes on after a Minimize, so
/// those taps are applied before the cover closes; that they are is the tester's
/// `minimize_keepsTheTapsMadeBeforeIt`, over a session whose calls wait. Here: what happens when one of them
/// is refused, on the real host.
@MainActor
@Suite("WorkoutStore minimize", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreMinimizeTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Scene = WorkoutScene

    /// Criterion 14, its other half: the cover does not close over a change that failed while "Minimize"
    /// waited for it.
    @Test("Minimize waits for the taps made before it; when one of them is refused the cover stays up and says so")
    func minimize_whileATapIsRefused_staysAndShowsIt() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        await scene.probe.fail(.append)
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        store.send(.minimize)
        #expect(store.exit == nil, "the tap made before Minimize has not been applied yet")
        #expect(store.model.header?.isEnabled == false)
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()
        #expect(store.exit == nil)
        #expect(store.dialog == .editFailed)
        #expect(store.model.header?.isEnabled == true)
        #expect(await scene.appends() == 1, "a tap made after Minimize was not queued")

        // With nothing waiting, Minimize closes the cover at once.
        store.send(.dismissFailure)
        store.send(.minimize)
        #expect(store.exit == .route(.minimized))
        task.cancel()
    }
}
