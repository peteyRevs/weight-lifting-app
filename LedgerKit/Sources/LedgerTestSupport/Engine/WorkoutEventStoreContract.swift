import Foundation
import LedgerDomain

/// `WorkoutEventStore`'s documented contract as named clauses, which every store runs: the in-memory
/// reference in `LedgerDomainTests` and `GRDBWorkoutEventStore` in `LedgerPersistenceTests`.
///
/// F04 wrote it in its test target; F05 moved it here, public API only, and added four clauses: a stamp
/// that a trip through seconds since 1970 alters, a `seq` of `UInt64.max`, non-finite stamps, and
/// `unreadableCount(for:)` of what the store itself wrote.
/// `EventStoreMutationAdversarialTests` (F04) checks that the clauses catch plausible store bugs.
public enum WorkoutEventStoreContract {
    /// One clause: it gets a fresh, empty store and returns `nil` when the store keeps the clause, or
    /// what the store did instead.
    public struct Clause: Sendable, CustomStringConvertible {
        public let name: String
        public let check: @Sendable (any WorkoutEventStore) async throws -> String?

        public var description: String {
            name
        }
    }

    public static let workout = EventBuilders.workoutID
    public static let other = WorkoutID(EventBuilders.uuid(0xF1B2))

    public static let clauses: [Clause] = [
        Clause(name: "append returns new envelopes in the order given; a re-append is a no-op", check: newInGivenOrder),
        Clause(
            name: "a conflict across batches throws and stores nothing from the batch",
            check: conflictAcrossBatches
        ),
        Clause(name: "a conflict within one batch throws and stores nothing", check: conflictWithinBatch),
        Clause(name: "same key and event, other stamp, is a conflict", check: conflictOnStampOnly),
        Clause(name: "keys are per workout", check: keysPerWorkout),
        Clause(name: "highestSeq is the maximum, per workout and device", check: highestSeqIsMaximum),
        Clause(name: "seq keeps all 64 bits, up to UInt64.max", check: fullWidthSeq),
        Clause(name: "every log is listed until compacted, whatever it holds", check: everyLogListed),
        Clause(name: "compact deletes and unlists one workout's log", check: compactOne),
        Clause(name: "a malformed envelope is stored like any other", check: malformedIsStored),
        Clause(name: "a non-finite date (±∞, NaN) is stored like any other", check: nonFiniteIsStored),
        Clause(name: "an envelope reads back once and exactly, to the last bit", check: readsBackExactlyOnce),
        Clause(name: "a store can read every envelope it stored: none is unreadable", check: noneUnreadable)
    ]

    /// Every clause's complaint about a store from `make`, which is called once per clause.
    public static func violations(of make: @Sendable () throws -> any WorkoutEventStore) async -> [String] {
        var found: [String] = []
        for clause in clauses {
            do {
                if let issue = try await clause.check(make()) {
                    found.append("\(clause.name): \(issue)")
                }
            } catch {
                found.append("\(clause.name): threw \(error)")
            }
        }
        return found
    }

    // MARK: Fixtures

    /// A `restSkipped` from `device` in `workout`, stamped `seconds` (default: `seq`) after the start.
    public static func skip(
        _ seq: UInt64,
        _ device: DeviceID = EventBuilders.watch,
        in workout: WorkoutID = EventBuilders.workoutID,
        at seconds: Double? = nil
    ) -> EventEnvelope {
        EventBuilders.envelope(
            .restSkipped,
            device: device,
            seq: seq,
            at: at(seconds ?? Double(seq)),
            workoutID: workout
        )
    }

    /// A "+30s" from the watch: a different envelope with `skip(seq)`'s key.
    public static func extend(_ seq: UInt64) -> EventEnvelope {
        let event = WorkoutEvent.restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: at(Double(seq)))
        return EventBuilders.envelope(event, device: EventBuilders.watch, seq: seq, at: at(Double(seq)))
    }

    /// A `started` for `workout`, from the phone at the fixture start.
    public static func start(_ workout: WorkoutID) -> EventEnvelope {
        let session = EventBuilders.session(EventBuilders.seedExercises, id: workout)
        return EventBuilders.envelope(.started(session), seq: 1, at: at(0), workoutID: workout)
    }

    /// The watch logging row (0, `set`) of the fixture session, done at `doneAt` and stamped `stamp`
    /// seconds after the start.
    public static func logged(set: Int, doneAt: Double, seq: UInt64, stamp: Double) -> EventEnvelope {
        let event = WorkoutEvent.setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, set),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: at(doneAt)
        )
        return EventBuilders.envelope(event, device: EventBuilders.watch, seq: seq, at: at(stamp))
    }

    /// `seconds` after the fixture start.
    public static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// `nil` when `body` throws `conflictingEnvelope(key)`, else what happened.
    static func expectConflict(
        _ key: EnvelopeKey,
        _ body: () async throws -> [EventEnvelope]
    ) async -> String? {
        do {
            return try await "stored \(body().count) instead of throwing"
        } catch let error as EngineError {
            return error == .conflictingEnvelope(key) ? nil : "threw \(error)"
        } catch {
            return "threw \(error)"
        }
    }
}
