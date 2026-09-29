import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// `WorkoutEventStore`'s documented contract, pinned on the in-memory reference store. F05 runs the
/// same clauses against its GRDB store: `WorkoutEventStoreContract.violations { GRDBStore(…) }`.
///
/// Fix round 2 (finding 10) folded in the tester's nine `StoreProbe`s, so the suite kills every mutant
/// in `EventStoreMutationAdversarialTests`, which stays as the suite's own guard.
@Suite("WorkoutEventStore · contract", .tags(.domain))
struct WorkoutEventStoreContractTests {
    @Test("The in-memory reference store keeps the clause", arguments: WorkoutEventStoreContract.clauses)
    func clause_holds(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(InMemoryEventStore())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }
}

/// The clauses of `WorkoutEventStore`'s doc comments. Each gets a fresh, empty store and returns `nil`
/// when the store keeps it, or what the store did instead.
enum WorkoutEventStoreContract {
    struct Clause: Sendable, CustomTestStringConvertible {
        let name: String
        let check: @Sendable (any WorkoutEventStore) async throws -> String?

        var testDescription: String {
            name
        }
    }

    static let workout = EventBuilders.workoutID
    static let other = WorkoutID(EventBuilders.uuid(0xF1B2))

    static let clauses: [Clause] = [
        Clause(name: "append returns new envelopes in the order given; a re-append is a no-op", check: newInGivenOrder),
        Clause(
            name: "a conflict across batches throws and stores nothing from the batch",
            check: conflictAcrossBatches
        ),
        Clause(name: "a conflict within one batch throws and stores nothing", check: conflictWithinBatch),
        Clause(name: "same key and event, other stamp, is a conflict", check: conflictOnStampOnly),
        Clause(name: "keys are per workout", check: keysPerWorkout),
        Clause(name: "highestSeq is the maximum, per workout and device", check: highestSeqIsMaximum),
        Clause(name: "every log is listed until compacted, whatever it holds", check: everyLogListed),
        Clause(name: "compact deletes and unlists one workout's log", check: compactOne),
        Clause(name: "a malformed envelope is stored like any other", check: malformedIsStored),
        Clause(name: "an envelope reads back once and exactly, to below a millisecond", check: readsBackExactlyOnce)
    ]

    /// Every clause's complaint about a store from `make`.
    static func violations(of make: @Sendable () -> any WorkoutEventStore) async -> [String] {
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
    static func skip(
        _ seq: UInt64,
        _ device: DeviceID = EventBuilders.watch,
        in workout: WorkoutID = EventBuilders.workoutID,
        at seconds: Double? = nil
    ) -> EventEnvelope {
        EngineAdv.env(.restSkipped, device, seq: seq, at: seconds ?? Double(seq), workoutID: workout)
    }

    /// A "+30s" from the watch: a different envelope with `skip(seq)`'s key.
    static func extend(_ seq: UInt64) -> EventEnvelope {
        EngineAdv.env(
            EngineAdv.extend(shown: true, tappedAt: Double(seq)),
            EventBuilders.watch,
            seq: seq,
            at: Double(seq)
        )
    }

    /// A `started` for `workout`, from the phone at the fixture start.
    static func start(_ workout: WorkoutID) -> EventEnvelope {
        EngineAdv.start(EventBuilders.session(EventBuilders.seedExercises, id: workout))
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

// MARK: - The clauses

extension WorkoutEventStoreContract {
    static func newInGivenOrder(_ store: any WorkoutEventStore) async throws -> String? {
        let (one, two, three) = (skip(1), skip(2), skip(3))
        let first = try await store.append([three, one])
        let second = try await store.append([one, two, three, two])
        let again = try await store.append([three, two, one])
        let stored = try await Set(store.envelopes(for: workout))
        return first == [three, one] && second == [two] && again.isEmpty && stored == [one, two, three]
            ? nil : "returned \(first.map(\.seq)), \(second.map(\.seq)), \(again.map(\.seq)); stored \(stored.count)"
    }

    static func conflictAcrossBatches(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([skip(1)])
        // The rival of a stored envelope last in its batch, then first.
        let last = await expectConflict(skip(1).key) { try await store.append([skip(2), extend(1)]) }
        let first = await expectConflict(skip(1).key) { try await store.append([extend(1), skip(3)]) }
        let stored = try await store.envelopes(for: workout)
        return last ?? first ?? (stored == [skip(1)] ? nil : "kept \(stored.map(\.seq)) from rejected batches")
    }

    static func conflictWithinBatch(_ store: any WorkoutEventStore) async throws -> String? {
        let issue = await expectConflict(skip(2).key) { try await store.append([skip(1), skip(2), extend(2)]) }
        let stored = try await store.envelopes(for: workout)
        let retry = try await store.append([skip(1), skip(2)])
        return issue ?? (stored.isEmpty && retry == [skip(1), skip(2)] ? nil : "stored \(stored.map(\.seq))")
    }

    static func conflictOnStampOnly(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([skip(1)])
        return await expectConflict(skip(1).key) { try await store.append([skip(1, at: 1.5)]) }
    }

    static func keysPerWorkout(_ store: any WorkoutEventStore) async throws -> String? {
        let (mine, theirs) = (skip(1), skip(1, in: other))
        let fresh = try await store.append([mine, theirs, mine])
        let listed = try await store.envelopes(for: other)
        return fresh == [mine, theirs] && listed == [theirs] ? nil : "returned \(fresh.count), listed \(listed.count)"
    }

    static func highestSeqIsMaximum(_ store: any WorkoutEventStore) async throws -> String? {
        let before = try await store.highestSeq(for: workout, device: EventBuilders.watch)
        _ = try await store.append([skip(7), skip(3), skip(2, EventBuilders.phone), skip(9, in: other)])
        let watch = try await store.highestSeq(for: workout, device: EventBuilders.watch)
        let phone = try await store.highestSeq(for: workout, device: EventBuilders.phone)
        let elsewhere = try await store.highestSeq(for: other, device: EventBuilders.phone)
        return before == nil && watch == 7 && phone == 2 && elsewhere == nil
            ? nil : "got \([before, watch, phone, elsewhere])"
    }

    /// Four logs: an envelope that arrived before its `started`, a live workout, a finished one and a
    /// discarded one. The host classifies them by replay, so the store must list all four.
    static func everyLogListed(_ store: any WorkoutEventStore) async throws -> String? {
        let (early, finished, discarded) = (
            WorkoutID(EventBuilders.uuid(0xF1E1)),
            WorkoutID(EventBuilders.uuid(0xF1E2)),
            WorkoutID(EventBuilders.uuid(0xF1E3))
        )
        _ = try await store.append([
            skip(1, in: early),
            start(workout),
            start(finished),
            EngineAdv.env(.finished(endedAt: engineTime(9)), seq: 2, at: 9, workoutID: finished),
            start(discarded),
            EngineAdv.env(.discarded(endedAt: engineTime(9)), seq: 2, at: 9, workoutID: discarded)
        ])
        let listed = try await Set(store.uncompactedWorkoutIDs())
        return listed == [early, workout, finished, discarded] ? nil : "listed \(listed.count) of 4"
    }

    static func compactOne(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([start(workout), skip(2), start(other)])
        try await store.compact(workout: workout)
        let mine = try await store.envelopes(for: workout)
        let listed = try await store.uncompactedWorkoutIDs()
        let seq = try await store.highestSeq(for: workout, device: EventBuilders.watch)
        let theirs = try await store.envelopes(for: other)
        return mine.isEmpty && listed == [other] && seq == nil && theirs.count == 1
            ? nil : "left \(mine.count) envelopes, listed \(listed), highestSeq \(String(describing: seq))"
    }

    /// The store judges keys, never contents: a malformed envelope (`isWellFormed`) is stored and
    /// returned like any other, so every device's log agrees; the engine ignores it.
    static func malformedIsStored(_ store: any WorkoutEventStore) async throws -> String? {
        let absurd = EngineAdv.env(
            EngineAdv.extend(7200, shown: true, tappedAt: 5), EventBuilders.watch, seq: 1, at: 5
        )
        let fresh = try await store.append([start(workout), absurd])
        let again = try await store.append([absurd])
        let stored = try await Set(store.envelopes(for: workout))
        return !absurd.isWellFormed && fresh.count == 2 && again.isEmpty && stored.contains(absurd)
            ? nil : "returned \(fresh.count), then \(again.count); stored it: \(stored.contains(absurd))"
    }

    /// Finding 22: `<` and the conflict check compare dates, so a store must keep them exactly. An HLC
    /// stamp and a payload date between milliseconds read back `==` (a store that writes milliseconds or
    /// ISO 8601 fails), and a re-append keeps one copy (the log is compared as an array, count and all).
    static func readsBackExactlyOnce(_ store: any WorkoutEventStore) async throws -> String? {
        let precise = EngineAdv.env(
            EngineAdv.logged(0, 0, doneAt: 10.493_826_8), EventBuilders.watch, seq: 1, at: 10.493_827_3
        )
        let fresh = try await store.append([precise])
        let again = try await store.append([precise])
        let stored = try await store.envelopes(for: workout)
        let exact = stored == [precise]
        return fresh == [precise] && again.isEmpty && exact
            ? nil : "returned \(fresh.count), then \(again.count); read back \(stored.count), exact: \(exact)"
    }
}
