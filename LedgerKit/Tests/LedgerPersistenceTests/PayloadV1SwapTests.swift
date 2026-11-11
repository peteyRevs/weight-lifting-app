import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S8 criterion 8: `exerciseSwapped` gained an optional `replacement` and the payload version stays 1. A
/// swap written before S8 has no such key: it must decode to `replacement == nil` and replay as it did, and a
/// swap that carries one must survive the event store.
@Suite("Payload version 1 · exerciseSwapped with and without a replacement (F10 S8)", .tags(.persistence))
struct PayloadV1SwapTests {
    static func committed(_ file: String) throws -> EventEnvelope {
        try EnvelopeCodec.decode(PayloadV1FixtureTests.fixture(file), version: 1)
    }

    @Test("A swap written before S8 (no replacement key) decodes, in version 1, to no replacement")
    func oldSwap_decodesWithoutAReplacement() throws {
        let raw = try PayloadV1FixtureTests.object(PayloadV1FixtureTests.fixture("event-exerciseSwapped"))
        let payload = try #require((raw["event"] as? NSDictionary)?["exerciseSwapped"] as? NSDictionary)
        #expect(payload["replacement"] == nil, "the committed payload has no replacement key")
        let envelope = try Self.committed("event-exerciseSwapped")
        guard case let .exerciseSwapped(index, exerciseID, name, alsoUpdateProgram, replacement) = envelope.event else {
            Issue.record("not a swap: \(envelope.event)")
            return
        }
        #expect(index == 0 && name == "Incline DB Press" && alsoUpdateProgram)
        #expect(try exerciseID == ExerciseID(#require(UUID(uuidString: "00000000-0000-0000-0000-000000000E02"))))
        #expect(replacement == nil)
        #expect(EnvelopeCodec.version == 1)
    }

    @Test("The old swap replays as it did: the id and the name change, and nothing else of the exercise")
    func oldSwap_replaysAsBefore() throws {
        let started = try Self.committed("event-started")
        let swapped = try Self.committed("event-exerciseSwapped")
        let before = try #require(WorkoutEngine.replay([started]))
        let after = try #require(WorkoutEngine.replay([started, swapped]))
        var expected = before.exercises[0]
        expected.exerciseID = try ExerciseID(#require(UUID(uuidString: "00000000-0000-0000-0000-000000000E02")))
        expected.name = "Incline DB Press"
        let isAsBefore = after.exercises[0] == expected
        #expect(isAsBefore)
        #expect(after.programUpdates == before.programUpdates) // the snapshot's entry already names E02
    }

    @Test("A swap with a replacement is written in version 1 and round-trips through the GRDB event store")
    func swapWithAReplacement_roundTripsThroughTheStore() async throws {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { PayloadV1.start })
        let started = try Self.committed("event-started")
        let swapped = try Self.committed("event-exerciseSwapped-replacement")
        guard case let .exerciseSwapped(_, _, _, _, replacement) = swapped.event else {
            Issue.record("not a swap: \(swapped.event)")
            return
        }
        #expect(replacement?.step == .kilograms(1.25) && replacement?.load == .kilograms(27.5))
        _ = try await store.append([started, swapped])
        let read = try await store.envelopes(for: PayloadV1.workout)
        let isWhole = read == [started, swapped]
        #expect(isWhole)
        let versions = try await queue.read { database in
            try Int.fetchAll(database, sql: "SELECT DISTINCT payload_version FROM workout_event")
        }
        #expect(versions == [1])
        let state = try #require(WorkoutEngine.replay(read))
        #expect(state.exercises[0].equipment == .dumbbell && state.exercises[0].step == .kilograms(1.25))
        #expect(state.exercises[0].sets.filter { !$0.isDone }.map(\.weight) == [SessionBuilder.dropLoad(
            of: .kilograms(27.5),
            step: .kilograms(1.25)
        )])
        #expect(state.exercises[0].sets.first?.weight == .pounds(185), "the done set keeps its weight")
    }
}
