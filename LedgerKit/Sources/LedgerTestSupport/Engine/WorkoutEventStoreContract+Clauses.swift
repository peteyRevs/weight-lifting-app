import Foundation
import LedgerDomain

/// The clauses of `WorkoutEventStore`'s doc comments (F04; F05 added `fullWidthSeq`, `nonFiniteIsStored`,
/// `noneUnreadable` and the second stamp in `readsBackExactlyOnce`).
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

    /// F05: `seq` is a `UInt64`. A store that keeps it in a signed column must still store, read back and
    /// order the seqs above `Int64.max`, so `highestSeq` is the unsigned maximum.
    static func fullWidthSeq(_ store: any WorkoutEventStore) async throws -> String? {
        let skips = [UInt64.max, 1 << 63, UInt64(Int64.max), 1].map { skip($0, at: 1) }
        let fresh = try await store.append(skips)
        let again = try await store.append(skips.reversed())
        let highest = try await store.highestSeq(for: workout, device: EventBuilders.watch)
        let stored = try await Set(store.envelopes(for: workout))
        return fresh == skips && again.isEmpty && highest == .max && stored == Set(skips)
            ? nil : "returned \(fresh.map(\.seq)), then \(again.count); highestSeq \(String(describing: highest))"
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
            EventBuilders.envelope(.finished(endedAt: at(9)), seq: 2, at: at(9), workoutID: finished),
            start(discarded),
            EventBuilders.envelope(.discarded(endedAt: at(9)), seq: 2, at: at(9), workoutID: discarded)
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
        let hour = WorkoutEvent.restExtended(amount: .seconds(7200), extendsShownRest: true, tappedAt: at(5))
        let absurd = EventBuilders.envelope(hour, device: EventBuilders.watch, seq: 1, at: at(5))
        let fresh = try await store.append([start(workout), absurd])
        let again = try await store.append([absurd])
        let stored = try await Set(store.envelopes(for: workout))
        return !absurd.isWellFormed && fresh.count == 2 && again.isEmpty && stored.contains(absurd)
            ? nil : "returned \(fresh.count), then \(again.count); stored it: \(stored.contains(absurd))"
    }

    /// F05: non-finite stamps (±∞, NaN) and a non-finite payload date are malformed, and stored like any
    /// other envelope. NaN is never `==` to itself (`Date`'s `==`), so that envelope is checked field by
    /// field and not re-appended: a store compares a re-append with what it holds, so it rejects it.
    static func nonFiniteIsStored(_ store: any WorkoutEventStore) async throws -> String? {
        let stamps = [Double.infinity, -.infinity, .nan].map(Date.init(timeIntervalSinceReferenceDate:))
        let skips = stamps.enumerated().map { index, stamp in
            EventBuilders.envelope(.restSkipped, device: EventBuilders.watch, seq: UInt64(index) + 1, at: stamp)
        }
        let ended = EventBuilders.envelope(
            .finished(endedAt: stamps[0]),
            device: EventBuilders.watch,
            seq: 4,
            at: at(4)
        )
        let fresh = try await store.append(skips + [ended])
        let again = try await store.append([skips[0], skips[1], ended])
        let stored = try await store.envelopes(for: workout).sorted { $0.seq < $1.seq }
        let kept = stored.map(\.wallClock.timeIntervalSinceReferenceDate)
        let exact = stored.count == 4 && Array(stored[0 ... 1]) == Array(skips[0 ... 1]) && stored[3] == ended
            && kept[2].isNaN && stored[2].key == skips[2].key && stored[2].event == skips[2].event
        return fresh.map(\.key) == (skips + [ended]).map(\.key) && again.isEmpty && exact
            ? nil : "returned \(fresh.count), then \(again.count); read back stamps \(kept)"
    }

    /// Finding 22: `<` and the conflict check compare dates, so a store must keep them exactly. Every
    /// date here lies between milliseconds, and F05 added the stamp 10.493_826_8, which a trip through
    /// seconds since 1970 alters (F04 round 4). A store that keeps milliseconds, ISO 8601 or seconds since
    /// 1970 fails, and a re-append keeps one copy (the log is compared as an array, count and all).
    static func readsBackExactlyOnce(_ store: any WorkoutEventStore) async throws -> String? {
        let precise = [
            logged(set: 0, doneAt: 10.493_826_8, seq: 1, stamp: 10.493_827_3),
            logged(set: 1, doneAt: 10.493_827_3, seq: 2, stamp: 10.493_826_8)
        ]
        let fresh = try await store.append(precise)
        let again = try await store.append(precise)
        let stored = try await store.envelopes(for: workout).sorted { $0.seq < $1.seq }
        let exact = stored == precise
        return fresh == precise && again.isEmpty && exact
            ? nil : "returned \(fresh.count), then \(again.count); read back \(stored.count), exact: \(exact)"
    }

    /// F05: everything a store wrote itself is readable, so `unreadableCount(for:)` is zero for its logs
    /// and for a workout it holds nothing of. (Only rows written by a later app version, or damaged ones,
    /// count; `UnreadableEventRowTests` covers those for the GRDB store.)
    static func noneUnreadable(_ store: any WorkoutEventStore) async throws -> String? {
        _ = try await store.append([start(workout), skip(2), logged(set: 0, doneAt: 3, seq: 3, stamp: 3)])
        let mine = try await store.unreadableCount(for: workout)
        let elsewhere = try await store.unreadableCount(for: other)
        return mine == 0 && elsewhere == 0 ? nil : "counted \(mine) and \(elsewhere) unreadable"
    }
}
