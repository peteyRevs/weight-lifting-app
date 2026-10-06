import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F11 S3 adversarial round 1, criterion 8: a call whose task is cancelled stores all of its change or none of
/// it, and throws `CancellationError` only when it stored none. The change here touches the program's row, every
/// week and every slot, so "half" has many shapes. Cancelled before the call, inside the change, while the call
/// waits behind another write, and at seeded moments around the commit; the store works afterwards.
@Suite("Adversarial F11 S3 · a cancelled update", .tags(.persistence), .timeLimit(.minutes(2)))
struct ProgramUpdateCancelAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Call = Task<Program, any Error>

    /// A change of many rows: one more in the name, every week's deload flag, every slot's sets.
    static let wide: @Sendable (Program) throws -> Program = { program in
        var changed = try UpdateKit.increment(program)
        for week in changed.weeks.indices {
            changed.weeks[week].isDeload.toggle()
        }
        for slot in changed.slotIDs {
            changed = changed.changing(slot) { $0.sets = 1 + $0.sets % 12 }
        }
        return changed
    }

    /// `nil` when `call` stored all of `wide` and returned it, or none of it and threw `CancellationError`.
    static func verdict(_ call: Call, on stores: LinkedStores, after before: Program?) async throws -> String? {
        let outcome = await call.result
        let after = try await UpdateKit.read(stores, 1)
        let (isNone, isAll) = try (after == before, after == before.map(wide))
        switch outcome {
        case let .success(returned):
            let isStored = returned == after
            return isAll && isStored ? nil : "returned, with all stored: \(isAll), none: \(isNone), own: \(isStored)"
        case let .failure(error) where error is CancellationError:
            return isNone ? nil : "threw CancellationError with \(isAll ? "all" : "a part") of its change stored"
        case let .failure(error):
            return "threw \(error), with all stored: \(isAll), none: \(isNone)"
        }
    }

    /// Whether `call` threw `CancellationError`: what the database does, every time, with a write whose task is
    /// cancelled before its transaction has committed (ruling 5: S13 relies on it).
    static func wasCancelled(_ call: Call) async -> Bool {
        if case let .failure(error) = await call.result {
            return error is CancellationError
        }
        return false
    }

    /// The store still takes an update and a workout's save, and keeps both.
    static func stillWorks(_ stores: LinkedStores) async throws -> String? {
        let before = try await UpdateKit.count(UpdateKit.read(stores, 1))
        let slot = try LinkedFixture.slot(4)
        let listed = try slot.with(misses: [0, 1, 2])
        let saved = await stores.save(LinkedFixture.workout(900), slots: [listed], droppingLog: false)
        let returned = try await UpdateKit.count(stores.programs.update(UpdateKit.one, UpdateKit.increment))
        let stored = try await UpdateKit.read(stores, 1)
        let misses = stored?.days.flatMap(\.slots).first { $0.id == slot.id }?.misses
        let isWhole = saved == "false" && returned == before + 1 && UpdateKit.count(stored) == before + 1
        return isWhole && misses == [0, 1, 2] ? nil : "afterwards: save \(saved.prefix(40)), count \(returned)"
    }

    @Test("Cancelled before the call: all or nothing", arguments: Place.allCases)
    func cancelledBeforeTheCall_storesAllOrNothing(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        let before = try await UpdateKit.read(stores, 1)
        let runs = UpdateTally()
        let call = Call {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await stores.programs.update(UpdateKit.one) { program in
                runs.add()
                return try Self.wide(program)
            }
        }
        let issue = try await Self.verdict(call, on: stores, after: before)
        #expect(issue == nil, "\(place): \(issue ?? "")")
        // Both stores say so of themselves: a task already cancelled never reaches the change.
        #expect(await Self.wasCancelled(call) && runs.isZero, "\(place): the change ran \(runs.count) times")
        let later = try await Self.stillWorks(stores)
        #expect(later == nil, "\(place): \(later ?? "")")
    }

    @Test("Cancelled from inside the change: all or nothing", arguments: Place.allCases, [false, true])
    func cancelledInsideTheChange_storesAllOrNothing(place: Place, afterComputing: Bool) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "inside\(afterComputing)")
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        let before = try await UpdateKit.read(stores, 1)
        let handle = Mutex<Call?>(nil)
        let (ready, start) = AsyncStream<Void>.makeStream()
        let call = Call {
            for await _ in ready {
                break
            }
            return try await stores.programs.update(UpdateKit.one) { program in
                if !afterComputing {
                    handle.withLock { $0?.cancel() }
                }
                let result = try Self.wide(program)
                handle.withLock { $0?.cancel() }
                return result
            }
        }
        handle.withLock { $0 = call }
        start.yield()
        let issue = try await Self.verdict(call, on: stores, after: before)
        #expect(issue == nil, "\(place): \(issue ?? "")")
        // Criterion 12: on every store, the in-memory one included.
        #expect(await Self.wasCancelled(call), "\(place): a write cancelled inside its change was stored")
        let later = try await Self.stillWorks(stores)
        #expect(later == nil, "\(place): \(later ?? "")")
    }

    @Test("Cancelled while it waits behind another write: all or nothing", arguments: Place.allCases, [0, 5, 200, 5000])
    func cancelledWhileWaiting_storesAllOrNothing(place: Place, yields: Int) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "waiting\(yields)")
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        let before = try await UpdateKit.read(stores, 1)
        let gate = UpdateGate()
        // Another update holds the store's write: its change waits at the gate (a test's device; a real change
        // must not wait). The limit lets a store that never runs the second call fail, not hang.
        let holder = Task {
            try await stores.programs.update(UpdateKit.two) { program in
                let wasOpened = gate.wait()
                return UpdateRefusal.changed(program) { $0.name = wasOpened ? "Held" : "Timed out" }
            }
        }
        await gate.untilReached()
        let runs = UpdateTally()
        let call = Call {
            try await stores.programs.update(UpdateKit.one) { program in
                runs.add()
                return try Self.wide(program)
            }
        }
        for _ in 0 ..< yields {
            await Task.yield()
        }
        call.cancel()
        gate.open()
        let held = try await holder.value
        let issue = try await Self.verdict(call, on: stores, after: before)
        #expect(issue == nil, "\(place), \(yields) yields: \(issue ?? "")")
        // Criterion 12: on every store, and the change is never called.
        #expect(await Self.wasCancelled(call) && runs.isZero, "\(place): cancelled while waiting, \(runs.count) runs")
        #expect(held.name == "Held", "the holding update's change was \(held.name)")
        let later = try await Self.stillWorks(stores)
        #expect(later == nil, "\(place): \(later ?? "")")
    }
}
