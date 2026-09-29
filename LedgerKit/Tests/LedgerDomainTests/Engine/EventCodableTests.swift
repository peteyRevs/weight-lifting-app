import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEvent · Codable", .tags(.domain))
struct EventCodableTests {
    @Test("Every event kind round-trips through JSON inside its envelope", arguments: ReduceTerminalTests.lateEvents)
    func envelope_roundTripsThroughJSON(event: WorkoutEvent) throws {
        let envelope = Engine.envelope(event, 12.345, from: Engine.watch, seq: 7)
        let data = try JSONEncoder().encode(envelope)
        #expect(try JSONDecoder().decode(EventEnvelope.self, from: data) == envelope)
    }

    @Test("A started snapshot keeps its program updates and units through JSON")
    func started_snapshotRoundTrips() throws {
        var session = EventBuilders.seedSession()
        session.units = .kg
        session.programUpdates = [SlotID(EventBuilders.uuid(1)): ExerciseID(EventBuilders.uuid(2))]
        let envelope = Engine.started(session)
        let decoded = try JSONDecoder().decode(EventEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded == envelope)
        #expect(EnvelopeKey(device: Engine.phone, seq: 1) == decoded.key)
    }

    @Test("EngineError names the conflicting key")
    func engineError_carriesKey() {
        let key = EnvelopeKey(device: Engine.watch, seq: 4)
        #expect(EngineError.conflictingEnvelope(key) == .conflictingEnvelope(key))
        #expect(EngineError.conflictingEnvelope(key) != .conflictingEnvelope(EnvelopeKey(device: Engine.phone, seq: 4)))
    }
}
