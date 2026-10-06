import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criteria 5 and 6: the rows an update writes. A change that gives the stored
/// program back, by whatever route, writes nothing; an edit writes the rows `save` writes for the same result,
/// and exactly the rows the edit names.
@Suite("Adversarial F11 S3 · the rows an update writes", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateRowsAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Stamps = ProgramTimestampAdversarialTests
    typealias Fixture = LinkedFixture

    @Test("A change that gives the stored program back writes no row", arguments: Place.allCases, [1, 2])
    func update_resultEqualToStored_writesNothing(place: Place, number: Int) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "unchanged\(number)")
        defer { try? directory?.remove() } // cleanup only
        let stored = try await UpdateKit.read(stores, number)
        var issues: [String] = []
        for route in UpdateRoutes.unchanged {
            let before = try await UpdateSnapshot(stores)
            stores.clock.advance()
            var (written, returned) = (0, Program?.none)
            if let queue = stores.queue {
                written = try await UpdateKit.rowsChanged(on: queue) {
                    returned = try await stores.programs.update(S2Kit.programID(number), route.change)
                }
            } else {
                returned = try await stores.programs.update(S2Kit.programID(number), route.change)
            }
            let difference = try await UpdateSnapshot(stores).difference(from: before)
            if difference != nil || written != 0 || returned != stored {
                let rows = "\(difference ?? "rows equal"), \(written) written"
                issues.append("\(route.name): \(rows), returned the stored program: \(returned == stored)")
            }
        }
        #expect(issues.isEmpty, "\(place), program \(number): \(issues.joined(separator: "; "))")
    }

    @Test("A change that gives the stored program back tells no watcher", arguments: [Place.database, .memory])
    func observeActive_resultEqualToStored_hearsNothing(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let heard = try await LinkedSaveObserverAdversarialTests.heardFirst(on: stores.programs.observeActive()) {
            for route in UpdateRoutes.unchanged {
                _ = try await stores.programs.update(UpdateKit.one, route.change)
                _ = try await stores.programs.update(UpdateKit.two, route.change)
            }
            // Program 2 is not the active one: an edit of it is not the watcher's to hear either.
            _ = try await stores.programs.update(UpdateKit.two) { program in
                UpdateRefusal.changed(program) { $0.name = "Unwatched" }
            }
            _ = try await stores.programs.update(UpdateKit.one) { program in
                UpdateRefusal.changed(program) { $0.name = "Marked" }
            }
        }
        #expect(heard??.name == "Marked", "\(place): heard a program named \(heard??.name ?? "nil") first")
    }

    @Test("A watcher hears an update of many rows as one whole program", arguments: [Place.database, .memory])
    func observeActive_updateOfManyRows_hearsTheResultWhole(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let edit = try #require(UpdateEdit.all.first { $0.name == "a day deleted" })
        let returned = LockedProgram()
        let heard = try await LinkedSaveObserverAdversarialTests.heardFirst(on: stores.programs.observeActive()) {
            try await returned.set(stores.programs.update(UpdateKit.one, edit.change))
        }
        let isWhole = heard == returned.value && heard != nil
        #expect(isWhole, "\(place): the first value heard has \(heard??.days.count ?? -1) days and is not the result")
    }

    /// The row keys (`"table id"`) whose columns differ between two readings, and the tables of rows that are new.
    static func changedRows(_ queue: DatabaseQueue, during body: () async throws -> Void) async throws -> [String] {
        let before = try await Stamps.stamps(queue)
        try await body()
        let after = try await Stamps.stamps(queue)
        return after.filter { before[$0.key] != $0.value }.map { key, stamp in
            let state = before[key] == nil ? "new" : (stamp.deleted == nil ? "written" : "deleted")
            // A miss's id is the store's to derive, so a miss is named by its table alone.
            return stamp.table == "slot_miss" ? "slot_miss \(state)" : "\(key.suffix(4)) \(stamp.table) \(state)"
        }.sorted()
    }

    @Test(
        "An edit writes exactly the rows it names, and what `save` writes for the same result",
        arguments: [Place.database, .file], Array(UpdateEdit.all.indices)
    )
    func update_edit_writesTheRowsSaveWrites(place: Place, index: Int) async throws {
        let edit = UpdateEdit.all[index]
        let (updated, first) = try await UpdateKit.make(place, "rowsA\(index)")
        let (saved, second) = try await UpdateKit.make(place, "rowsB\(index)")
        defer { // cleanup only
            try? first?.remove()
            try? second?.remove()
        }
        let (queue, twin) = try (#require(updated.queue), #require(saved.queue))
        updated.clock.advance()
        saved.clock.advance()
        let rows = try await Self.changedRows(queue) {
            _ = try await updated.programs.update(UpdateKit.one, edit.change)
        }
        let stored = try #require(try await UpdateKit.read(saved, 1))
        let savedRows = try await Self.changedRows(twin) {
            try await saved.programs.save(edit.change(stored))
        }
        let (isExact, isAsSave) = (rows == edit.rows.sorted(), rows == savedRows)
        #expect(isExact, "\(edit.name): update wrote \(rows)")
        #expect(isAsSave, "\(edit.name): save wrote \(savedRows)")
        let difference = try await LinkedStores.difference(saved.dump(), updated.dump())
        #expect(difference == nil, "\(edit.name), save against update: \(difference ?? "")")
    }

    @Test("In memory an edit leaves what `save` leaves, and returns what is stored", arguments: UpdateEdit.all.indices)
    func update_editInMemory_leavesWhatSaveLeaves(index: Int) async throws {
        let edit = UpdateEdit.all[index]
        let (updated, _) = try await UpdateKit.make(.memory)
        let (saved, _) = try await UpdateKit.make(.memory)
        let database = try await LinkedStores.make(.database)
        let returned = try await updated.programs.update(UpdateKit.one, edit.change)
        let onDatabase = try await database.programs.update(UpdateKit.one, edit.change)
        try await saved.programs.save(edit.change(Fixture.program(1)))
        let (left, right) = try await (UpdateSnapshot(updated), UpdateSnapshot(saved))
        let difference = left.difference(from: right)
        #expect(difference == nil, "\(edit.name), update against save: \(difference ?? "")")
        let isSameOnBoth = returned == onDatabase
        #expect(isSameOnBoth, "\(edit.name): the database returned another program than the memory")
        let isTheChange = try returned == edit.change(Fixture.program(1))
        #expect(isTheChange, "\(edit.name): the result is not the change applied to the stored program")
    }
}
