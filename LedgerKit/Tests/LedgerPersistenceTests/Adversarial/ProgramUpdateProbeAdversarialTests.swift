import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F11 S3 adversarial round 1, criterion 9 and what the app does around an update: the probe forwards
/// `update`, holds it and fails it (S13's store test holds the first write); a held update takes the program
/// as it is stored when it is let go; and updates survive a relaunch of the database file.
@Suite("Adversarial F11 S3 · the probe, and a relaunch", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateProbeAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Fixture = LinkedFixture

    static func probed(_ stores: LinkedStores, yields: Int = 0) -> ProbedStores {
        ProbedStores(events: stores.events, workouts: stores.workouts, programs: stores.programs, yields: yields)
    }

    @Test(
        "The probe passes an update on, with its result and its errors, and records each call",
        arguments: [Place.database, .memory]
    )
    func probe_forwardsUpdate(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let probed = Self.probed(stores, yields: 3)
        let returned = try await probed.programs.update(UpdateKit.one, ProgramUpdateLostAdversarialTests.edit)
        let isStored = try await returned == UpdateKit.read(stores, 1)
        let isTheEdit = try returned == ProgramUpdateLostAdversarialTests.edit(Fixture.program(1))
        #expect(isStored && isTheEdit, "stored: \(isStored), the edit: \(isTheEdit)")
        let outcomes = await [
            UpdateKit.attempt(probed.programs, S2Kit.programID(404)) { $0 },
            UpdateKit.attempt(probed.programs, UpdateKit.one) { _ in throw UpdateKit.Thrown(code: 3) },
            UpdateKit.attempt(probed.programs, UpdateKit.one) { _ in try Fixture.program(2) }
        ]
        #expect(outcomes == [
            "\(RepositoryError.missingRow("program \(ColumnCodec.text(S2Kit.programID(404)))"))",
            "\(UpdateKit.Thrown(code: 3))",
            UpdateRefusal.duplicate(UpdateKit.two)
        ], "\(outcomes)")
        #expect(await probed.probe.calls == Array(repeating: .updateProgram, count: 4))
    }

    @Test(
        "A held update stores nothing while it waits, and takes the program as stored when it is let go",
        arguments: [Place.database, .memory]
    )
    func probe_heldUpdate_appliesToWhatIsStoredAtRelease(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let probed = Self.probed(stores)
        let before = try await UpdateSnapshot(stores)
        let calls = UpdateTally()
        await probed.probe.hold(.updateProgram)
        let held = Task {
            try await probed.programs.update(UpdateKit.one) { program in
                calls.add()
                return ProgramUpdateLostAdversarialTests.edit(program)
            }
        }
        try await probed.probe.waitUntilHeld()
        let waiting = try await UpdateSnapshot(stores).difference(from: before)
        #expect(waiting == nil && calls.isZero, "while held: \(waiting ?? "nothing stored"), \(calls.count) calls")
        // A workout finishes meanwhile, and a second update that is not held goes through.
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let workout = Fixture.workout(1, updates: [slot.id: swapped])
        _ = await stores.save(workout, slots: [Fixture.missing(slot, [0, 2])], droppingLog: false)
        _ = try await probed.programs.update(UpdateKit.one) { program in
            UpdateRefusal.changed(program) { $0.name = "Meanwhile" }
        }
        await probed.probe.release()
        let returned = try await held.value
        let line = try await ProgramUpdateLostAdversarialTests.line(stores)
        #expect(line == "\(LinkedDifference.name(swapped)) [0, 2] 11 Edited", "\(place): \(line)")
        #expect(returned.name == "Meanwhile" && calls.count == 1, "\(returned.name), \(calls.count) calls")
        #expect(await probed.probe.calls.count { $0 == .updateProgram } == 2)
    }

    @Test(
        "An update made to fail stores nothing before the store, and everything when the answer is lost",
        arguments: [Place.database, .memory]
    )
    func probe_failedUpdate_storesNothingOrAll(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let probed = Self.probed(stores)
        try await UpdateKit.zero(stores)
        let before = try await UpdateSnapshot(stores)
        await probed.probe.fail(.updateProgram)
        let refused = await UpdateKit.attempt(probed.programs, UpdateKit.one, UpdateKit.increment)
        let difference = try await UpdateSnapshot(stores).difference(from: before)
        #expect(refused == "\(StoreProbe.Refusal(call: .updateProgram))" && difference == nil, "\(refused)")
        await probed.probe.fail(.updateProgram, afterStoring: true)
        let lost = await UpdateKit.attempt(probed.programs, UpdateKit.one, UpdateKit.increment)
        let stored = try await UpdateKit.count(UpdateKit.read(stores, 1))
        #expect(lost == "\(StoreProbe.Refusal(call: .updateProgram))" && stored == 1, "\(lost), \(stored) stored")
        let healed = try await UpdateKit.count(probed.programs.update(UpdateKit.one, UpdateKit.increment))
        #expect(healed == 2)
    }

    @Test(
        "A held update whose task is cancelled stores all or nothing when it is let go",
        arguments: [Place.database, .memory]
    )
    func probe_heldUpdateCancelled_storesAllOrNothing(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let probed = Self.probed(stores)
        try await UpdateKit.zero(stores)
        let before = try await UpdateKit.read(stores, 1)
        await probed.probe.hold(.updateProgram)
        let held = Task { try await probed.programs.update(UpdateKit.one, ProgramUpdateCancelAdversarialTests.wide) }
        try await probed.probe.waitUntilHeld()
        held.cancel()
        await probed.probe.release()
        let issue = try await ProgramUpdateCancelAdversarialTests.verdict(held, on: stores, after: before)
        #expect(issue == nil, "\(place): \(issue ?? "")")
    }

    @Test("A change that starts another update, and does not wait for it, gets both stored", arguments: Place.allCases)
    func change_startingAnotherUpdate_bothAreStored(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        let inner = Mutex<Task<Program, any Error>?>(nil)
        let outer = try await stores.programs.update(UpdateKit.one) { program in
            inner.withLock { started in
                started = Task { try await stores.programs.update(UpdateKit.one, UpdateKit.increment) }
            }
            return try UpdateKit.increment(program)
        }
        let later = try await inner.withLock { $0 }?.value
        let stored = try await UpdateKit.count(UpdateKit.read(stores, 1))
        #expect(UpdateKit.count(outer) == 1 && UpdateKit.count(later) == 2 && stored == 2, "\(place): \(stored) stored")
    }

    @Test("Updates and a workout's save are all there after the file is closed and opened again")
    func relaunch_keepsEveryUpdate() async throws {
        let (stores, directory) = try await UpdateKit.make(.file)
        defer { try? directory?.remove() } // cleanup only
        let url = try #require(directory).file("ledger.sqlite")
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        var last: Program?
        for edit in UpdateEdit.all.prefix(13) {
            last = try await stores.programs.update(UpdateKit.one, edit.change)
        }
        _ = await stores.save(
            Fixture.workout(1, updates: [slot.id: swapped]),
            slots: [Fixture.missing(slot, [2])],
            droppingLog: false
        )
        last = try await stores.programs.update(UpdateKit.one, ProgramUpdateLostAdversarialTests.edit)
        let expected = try UpdateEdit.all.prefix(13).reduce(Fixture.program(1)) { try $1.change($0) }
            .changing(slot.id) { changed in
                changed.misses = [2]
                changed.exerciseID = swapped
            }
        try stores.queue?.close()
        let reopened = try UpdateKit.opened(url, stores.clock)
        let stored = try await UpdateKit.read(reopened, 1)
        let (isLast, isExpected) = (stored == last, stored == ProgramUpdateLostAdversarialTests.edit(expected))
        #expect(isLast && isExpected, "after the relaunch: the last result \(isLast), the model \(isExpected)")
        // The slot one of the edits removed is still a row, deleted, and the next update leaves it so.
        let again = try await UpdateKit.count(reopened.programs.update(UpdateKit.one) { program in
            UpdateRefusal.changed(program) { $0.name = "7" }
        })
        let removed = try await reopened.queue?.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM slot WHERE deleted_at IS NOT NULL")
        }
        #expect(again == 7 && removed == 1, "counted \(again), \(removed ?? -1) deleted slots")
        try reopened.queue?.close()
    }
}
