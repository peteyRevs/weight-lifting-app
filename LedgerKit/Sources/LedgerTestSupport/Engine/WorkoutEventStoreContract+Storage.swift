import Foundation
import LedgerDomain

/// What an event store refuses at its storage boundary (F07 S1 fix round 1, finding F7-2): an envelope
/// `EnvelopeCodec` cannot encode, such as one logging a NaN weight, which has no exact text. Separate from
/// `clauses` because F04's store models keep envelopes as values: the GRDB store and LedgerFakes'
/// `InMemoryWorkoutEventStore`, which both store the encoding, run both lists.
public extension WorkoutEventStoreContract {
    static let storageClauses: [Clause] = [
        Clause(
            name: "an envelope with no encoding (a NaN weight) throws EncodingError and stores nothing from the batch",
            check: refusesWhatHasNoEncoding
        )
    ]
}

extension WorkoutEventStoreContract {
    static func refusesWhatHasNoEncoding(_ store: any WorkoutEventStore) async throws -> String? {
        let event = WorkoutEvent.setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: Weight(grams: .nan),
            reps: Reps(clamping: 5),
            doneAt: at(2)
        )
        let unencodable = EventBuilders.envelope(event, device: EventBuilders.watch, seq: 2, at: at(2))
        do {
            _ = try await store.append([skip(1), unencodable])
            return "appended an envelope logging a NaN weight"
        } catch is EncodingError {
            let stored = try await store.envelopes(for: workout)
            return stored.isEmpty ? nil : "kept \(stored.map(\.seq)) from the refused batch"
        }
    }
}
