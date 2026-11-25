#if os(iOS)
    import Dependencies
    import Foundation
    @testable import LedgerAppKit
    import LedgerDependencies
    import LedgerDomain
    import LedgerFakes
    import LedgerHealth
    import Testing

    /// The phone's health store, wired (F16 S3a): bound with the database's stores, and handed the mirrored session's
    /// recovery when the system relaunches the app for it.
    @Suite("Health wiring", .timeLimit(.minutes(1)))
    struct HealthWiringTests {
        @Test("The live environment holds the phone's LiveHealthStore; a booted composition binds the one it is given")
        func composition_bindsTheHealthStore() {
            #expect(AppComposition.Environment.live(arguments: ["Ledger"]).healthStore is LiveHealthStore)
            let harness = Harness()
            defer { harness.remove() }
            let fake = FakeHealthStore(authorization: .authorized)
            let composition = harness.composition(healthStore: fake)
            composition.boot()
            let bound = withDependencies { composition.bind(&$0) } operation: {
                @Dependency(\.healthStore) var healthStore
                return healthStore
            }
            #expect(bound as? FakeHealthStore === fake)
        }

        @Test("The delegate hands a relaunch's recovery to the health store")
        func delegate_recoversTheMirroredSession() async {
            let session = FakeHealthStore.Session(workoutID: WorkoutID(Fixtures.uuid(1)), start: Fixtures.now)
            let fake = FakeHealthStore(authorization: .authorized, recoverable: session)
            let delegate = withDependencies { $0.healthStore = fake } operation: { PhoneAppDelegate() }
            delegate.recover()
            await delegate.recovery?.value
            #expect(await fake.activeSession == session)
            let empty = withDependencies { $0.healthStore = FakeHealthStore() } operation: { PhoneAppDelegate() }
            empty.recover()
            await empty.recovery?.value // nothing to take up: the delegate only logs
        }
    }
#endif
