import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// `WorkoutEventStore`'s documented contract, pinned on the in-memory reference store. F05 runs the
/// same assertions against its GRDB store.
@Suite("WorkoutEventStore · contract", .tags(.domain))
struct WorkoutEventStoreContractTests {
    static let other = WorkoutID(EventBuilders.uuid(0xF101))

    /// A `restSkipped` from `device` in `workout`, at `seq` seconds.
    static func skip(
        _ seq: UInt64,
        from device: DeviceID = Engine.watch,
        in workout: WorkoutID? = nil
    ) -> EventEnvelope {
        let workoutID = workout ?? EventBuilders.workoutID
        return EventBuilders.envelope(
            .restSkipped,
            device: device,
            seq: seq,
            at: Engine.at(Double(seq)),
            workoutID: workoutID
        )
    }

    @Test("append returns only the envelopes it newly stored, in the order given; a re-append is a no-op")
    func append_returnsNewEnvelopes_andIsIdempotent() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let (first, second, third) = (Self.skip(1), Self.skip(2), Self.skip(3))
        #expect(try await store.append([first, second]) == [first, second])
        #expect(try await store.append([second, third, third, first]) == [third])
        #expect(try await store.append([first]).isEmpty)
        #expect(try await Set(store.envelopes(for: EventBuilders.workoutID)) == [first, second, third])
    }

    @Test("A different envelope with a stored key is rejected, and nothing from its batch is stored")
    func append_conflictingKey_throwsAndStoresNothing() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let stored = Self.skip(1)
        let conflicting = EventBuilders.envelope(
            .restExtended(amount: .seconds(30)),
            device: Engine.watch,
            seq: 1,
            at: Engine.at(1)
        )
        _ = try await store.append([stored])
        await #expect(throws: EngineError.conflictingEnvelope(stored.key)) {
            try await store.append([Self.skip(2), conflicting])
        }
        #expect(try await store.envelopes(for: EventBuilders.workoutID) == [stored])
    }

    @Test("Keys are per workout: the same (device, seq) is a different envelope in another workout")
    func keys_arePerWorkout() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let mine = Self.skip(1)
        let theirs = Self.skip(1, in: Self.other)
        #expect(try await store.append([mine, theirs]) == [mine, theirs])
        #expect(try await store.envelopes(for: Self.other) == [theirs])
    }

    @Test("highestSeq is per workout and device; nil before the device has stored anything")
    func highestSeq_perWorkoutAndDevice() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        _ = try await store.append([
            Self.skip(3),
            Self.skip(7),
            Self.skip(2, from: Engine.phone),
            Self.skip(9, in: Self.other)
        ])
        #expect(try await store.highestSeq(for: EventBuilders.workoutID, device: Engine.watch) == 7)
        #expect(try await store.highestSeq(for: EventBuilders.workoutID, device: Engine.phone) == 2)
        #expect(try await store.highestSeq(for: Self.other, device: Engine.phone) == nil)
    }

    @Test("Finding 8: a log with a terminal is unmaterialized, not live, until it is compacted")
    func liveAndUnmaterialized_untilCompacted() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let live = EventBuilders.session(EventBuilders.seedExercises, id: Self.other)
        _ = try await store.append([
            EventBuilders.envelope(.started(live), seq: 1, at: Engine.at(0), workoutID: Self.other),
            Engine.started(),
            Engine.envelope(.finished(endedAt: Engine.at(60)), 60, seq: 2)
        ])
        #expect(try await store.liveWorkoutIDs() == [Self.other])
        #expect(try await store.unmaterializedWorkoutIDs() == [EventBuilders.workoutID])
        try await store.compact(workout: EventBuilders.workoutID)
        #expect(try await store.unmaterializedWorkoutIDs().isEmpty)
        #expect(try await store.envelopes(for: EventBuilders.workoutID).isEmpty)
        #expect(try await store.liveWorkoutIDs() == [Self.other])
    }
}
