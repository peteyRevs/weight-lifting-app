#if os(watchOS)
    import Dependencies
    import Foundation
    import HealthKit
    import LedgerDependencies
    import LedgerDomain
    import LedgerFakes
    import LedgerHealth
    @testable import LedgerWatchAppKit
    import Testing

    /// The watch's health store, wired (F16 S3a): bound with the database's stores, and handed the phone's start
    /// request and the system's recovery by the app's delegate.
    @Suite("Health wiring", .timeLimit(.minutes(1)))
    struct HealthWiringTests {
        @Test("The live environment holds the watch's LiveHealthStore; a booted composition binds the one it is given")
        func composition_bindsTheHealthStore() {
            #expect(WatchComposition.Environment.live(arguments: ["LedgerWatch"]).healthStore is LiveHealthStore)
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

        @Test("The delegate reports the phone's start request, and hands the system's recovery to the store")
        func delegate_startAndRecovery() async {
            let session = FakeHealthStore.Session(workoutID: WorkoutID(Fixtures.uuid(1)), start: Fixtures.now)
            let fake = FakeHealthStore(authorization: .authorized, recoverable: session)
            let delegate = withDependencies { $0.healthStore = fake } operation: { WatchAppDelegate() }
            delegate.handle(HKWorkoutConfiguration())
            delegate.handleActiveWorkoutRecovery()
            await delegate.recovery?.value
            #expect(await fake.activeSession == session)
            #expect(await HealthStoreContractEvents.next(2, of: fake.events) == [.startRequestedByPhone, .recovered])
            let empty = withDependencies { $0.healthStore = FakeHealthStore() } operation: { WatchAppDelegate() }
            empty.handleActiveWorkoutRecovery()
            await empty.recovery?.value // nothing to take up: the delegate only logs
        }
    }

    /// The next values of a stream.
    enum HealthStoreContractEvents {
        static func next<Element: Sendable>(_ count: Int, of stream: AsyncStream<Element>) async -> [Element] {
            var iterator = stream.makeAsyncIterator()
            var values: [Element] = []
            while values.count < count, let value = await iterator.next() {
                values.append(value)
            }
            return values
        }
    }
#endif
