import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 5 where the host's stores are not one database: "recovery's row
/// "saved, not compacted" remains only for stores that are not one database", and the protocol: "Only a host
/// whose stores are not one database saves the workout and drops its log in two steps." Here the host is
/// given a workout repository and an event store that do not share a database, each real: nothing in the
/// host's initialiser says they must.
@Suite("Adversarial F10 S3 · a host whose stores are not one database", .tags(.sync), .timeLimit(.minutes(1)))
struct HostMixedStoresAdversarialTests {
    /// A workout repository with its programs, and the event store a host is given beside them.
    struct Stores: Sendable {
        let workouts: any WorkoutRepository
        let programs: any ProgramRepository
        let events: any WorkoutEventStore
    }

    struct Mix: Sendable, CustomStringConvertible {
        let description: String
        let make: @Sendable () throws -> Stores
    }

    static func database() throws -> LedgerStores {
        try LedgerStores(LedgerDatabase.inMemory(), deviceID: EventBuilders.phone, now: { EventBuilders.start })
    }

    static let mixes: [Mix] = [
        Mix(description: "the database's repository, an in-memory event store") {
            let stores = try database()
            return Stores(workouts: stores.workouts, programs: stores.programs, events: InMemoryWorkoutEventStore())
        },
        Mix(description: "the database's repository, another database's event store") {
            let (stores, other) = try (database(), database())
            return Stores(workouts: stores.workouts, programs: stores.programs, events: other.events)
        },
        Mix(description: "the fakes' linked repository, another event store") {
            let stores = InMemoryStores()
            return Stores(workouts: stores.workouts, programs: stores.programs, events: InMemoryWorkoutEventStore())
        },
        Mix(description: "the fakes' linked repository, the database's event store") {
            let stores = InMemoryStores()
            return try Stores(workouts: stores.workouts, programs: stores.programs, events: database().events)
        }
    ]

    static func host(_ stores: Stores) -> LocalWorkoutSessionActor {
        LocalWorkoutSessionActor(
            events: stores.events, workouts: stores.workouts, programs: stores.programs,
            device: EventBuilders.phone, now: { EventBuilders.start }
        )
    }

    /// Expected: a finished workout is in history and its log is gone from the host's event store, whichever
    /// store that is; a log that stays is saved again at every launch, with the misses and the program
    /// changes of an old workout written over whatever the lifter has done since.
    @Test("After a finish the log is gone from the event store the host was given", arguments: mixes)
    func finish_eventStoreElsewhere_dropsItsLog(mix: Mix) async throws {
        let stores = try mix.make()
        let host = Self.host(stores)
        try await host.start(Seam.session(1))
        try await host.apply(Seam.logged(0, 0, in: 1))
        _ = try await host.finish(endedAt: SiegeScene.end)
        #expect(try await stores.workouts.recent(limit: 9).map(\.id) == [Seam.workout(1)])
        let left = try await stores.events.uncompactedWorkoutIDs()
        #expect(left.isEmpty, "\(left.count) log left in the host's event store")
        #expect(try await host.current() == nil)
    }

    @Test("After a relaunch nothing of a finished workout is left to save again", arguments: mixes)
    func relaunch_afterAFinish_findsNoLogToSaveAgain(mix: Mix) async throws {
        let stores = try mix.make()
        let host = Self.host(stores)
        try await host.start(Seam.session(1))
        _ = try await host.finish(endedAt: SiegeScene.end)
        try await stores.workouts.delete(id: Seam.workout(1))
        let relaunched = Self.host(stores)
        #expect(try await relaunched.resumeFromStore() == nil)
        let cameBack = try await stores.workouts.workout(id: Seam.workout(1)) != nil
        #expect(!cameBack, "a workout the lifter deleted from history was saved again at the next launch")
        #expect(try await stores.events.uncompactedWorkoutIDs().isEmpty)
    }

    @Test("A discard drops the log from the event store the host was given", arguments: mixes)
    func discard_eventStoreElsewhere_dropsItsLog(mix: Mix) async throws {
        let stores = try mix.make()
        let host = Self.host(stores)
        try await host.start(Seam.session(1))
        try await host.discard(endedAt: SiegeScene.end)
        #expect(try await stores.events.uncompactedWorkoutIDs().isEmpty)
        #expect(try await stores.workouts.recent(limit: 9).isEmpty)
    }
}
