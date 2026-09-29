import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Probes of `WorkoutEventStore`'s documented contract (its doc comments after fix round 1), written to
/// kill the mutants in `MutantEventStore`. Each probe gets a fresh, empty store and returns `nil` when the
/// store keeps the clause, or what it did instead. F05 can run `violations` against its GRDB store.
enum StoreProbe {
    typealias Probe = @Sendable (any WorkoutEventStore) async throws -> String?

    static let other = WorkoutID(EventBuilders.uuid(0xF1B2))

    /// A `restSkipped` from `device` in `workout`, stamped `seconds` (default: `seq`) after the start.
    static func skip(
        _ seq: UInt64,
        _ device: DeviceID = EngineAdv.watch,
        in workout: WorkoutID = EngineAdv.workoutID,
        at seconds: Double? = nil
    ) -> EventEnvelope {
        EngineAdv.env(.restSkipped, device, seq: seq, at: seconds ?? Double(seq), workoutID: workout)
    }

    /// A "+30s" from the watch: a different envelope with `skip(seq)`'s key.
    static func extend(_ seq: UInt64) -> EventEnvelope {
        EngineAdv.env(.restExtended(amount: .seconds(30)), EngineAdv.watch, seq: seq, at: Double(seq))
    }

    static let all: [(name: String, probe: Probe)] = [
        ("append returns new envelopes in the order given", newInGivenOrder),
        ("a conflict across batches throws and stores nothing", conflictAcrossBatches),
        ("a conflict within one batch throws and stores nothing", conflictWithinBatch),
        ("same key and event, other stamp, is a conflict", conflictOnStampOnly),
        ("keys are per workout", keysPerWorkout),
        ("highestSeq is the maximum, per workout and device", highestSeqIsMaximum),
        ("live needs a started", liveNeedsStarted),
        ("finished and discarded are both terminal", bothTerminals),
        ("compact deletes one workout's log", compactOne)
    ]

    /// Every probe's complaint about a store from `make`.
    static func violations(of make: @Sendable () -> any WorkoutEventStore) async -> [String] {
        var found: [String] = []
        for (name, probe) in all {
            do {
                if let issue = try await probe(make()) {
                    found.append("\(name): \(issue)")
                }
            } catch {
                found.append("\(name): threw \(error)")
            }
        }
        return found
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

// MARK: - The probes

extension StoreProbe {
    static func newInGivenOrder(_ store: any WorkoutEventStore) async throws -> String? {
        let (one, two, three) = (skip(1), skip(2), skip(3))
        let first = try await store.append([three, one])
        let second = try await store.append([one, two, three, two])
        let again = try await store.append([three, two, one])
        return first == [three, one] && second == [two] && again.isEmpty
            ? nil : "returned \(first.map(\.seq)), \(second.map(\.seq)), \(again.map(\.seq))"
    }

    static func conflictAcrossBatches(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([skip(1)])
        // The rival of a stored envelope last in its batch, then first.
        let last = await expectConflict(skip(1).key) { try await store.append([skip(2), extend(1)]) }
        let first = await expectConflict(skip(1).key) { try await store.append([extend(1), skip(3)]) }
        let stored = try await store.envelopes(for: EngineAdv.workoutID)
        return last ?? first ?? (stored == [skip(1)] ? nil : "kept \(stored.map(\.seq)) from rejected batches")
    }

    static func conflictWithinBatch(_ store: any WorkoutEventStore) async throws -> String? {
        let issue = await expectConflict(skip(2).key) { try await store.append([skip(1), skip(2), extend(2)]) }
        let stored = try await store.envelopes(for: EngineAdv.workoutID)
        return issue ?? (stored.isEmpty ? nil : "stored \(stored.map(\.seq))")
    }

    static func conflictOnStampOnly(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([skip(1)])
        return await expectConflict(skip(1).key) { try await store.append([skip(1, at: 1.5)]) }
    }

    static func keysPerWorkout(_ store: any WorkoutEventStore) async throws -> String? {
        let (mine, theirs) = (skip(1), skip(1, in: other))
        let fresh = try await store.append([mine, theirs])
        let listed = try await store.envelopes(for: other)
        return fresh == [mine, theirs] && listed == [theirs] ? nil : "returned \(fresh.count), listed \(listed.count)"
    }

    static func highestSeqIsMaximum(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([skip(7), skip(3), skip(2, EngineAdv.phone), skip(9, in: other)])
        let watch = try await store.highestSeq(for: EngineAdv.workoutID, device: EngineAdv.watch)
        let phone = try await store.highestSeq(for: EngineAdv.workoutID, device: EngineAdv.phone)
        let elsewhere = try await store.highestSeq(for: other, device: EngineAdv.phone)
        return watch == 7 && phone == 2 && elsewhere == nil ? nil : "got \([watch, phone, elsewhere])"
    }

    static func liveNeedsStarted(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([EngineAdv.env(EngineAdv.logged(0, 0, doneAt: 5), EngineAdv.watch, seq: 1, at: 5)])
        let live = try await store.liveWorkoutIDs()
        _ = try await store.append([EngineAdv.start()])
        let started = try await store.liveWorkoutIDs()
        return live.isEmpty && started == [EngineAdv.workoutID] ? nil : "live \(live.count), then \(started.count)"
    }

    static func bothTerminals(_ store: any WorkoutEventStore) async throws -> String? {
        let finished = EngineAdv.start(EventBuilders.session(EventBuilders.seedExercises, id: other))
        _ = try await store.append([
            EngineAdv.start(),
            EngineAdv.env(.discarded(endedAt: engineTime(9)), seq: 2, at: 9),
            finished,
            EngineAdv.env(.finished(endedAt: engineTime(9)), seq: 2, at: 9, workoutID: other)
        ])
        let live = try await store.liveWorkoutIDs()
        let ended = try await Set(store.unmaterializedWorkoutIDs())
        return live.isEmpty && ended == [EngineAdv.workoutID, other] ? nil : "live \(live), ended \(ended)"
    }

    static func compactOne(_ store: any WorkoutEventStore) async throws -> String? {
        let theirs = EngineAdv.start(EventBuilders.session(EventBuilders.seedExercises, id: other))
        _ = try await store.append([EngineAdv.start(), theirs])
        try await store.compact(workout: EngineAdv.workoutID)
        let mine = try await store.envelopes(for: EngineAdv.workoutID)
        let live = try await store.liveWorkoutIDs()
        return mine.isEmpty && live == [other] ? nil : "left \(mine.count) envelopes, live \(live)"
    }
}
