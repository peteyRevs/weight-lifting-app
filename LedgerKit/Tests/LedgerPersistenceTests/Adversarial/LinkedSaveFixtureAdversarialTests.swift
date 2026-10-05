import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 7: "No migration. The schema and the version-1 fixtures are
/// unchanged." A copy of `Fixtures/db-v001.sqlite`, the file version 1's code wrote, brought up to date by
/// the migrations that were there before S3, takes a save with a program change and its log dropped as a new
/// database does, and its schema is what it was. (`git diff 95ac9b8 f8c513d` shows no change to
/// `Migrations.swift` or to any file under `Fixtures/`.)
@Suite("Adversarial F10 S3 · no migration", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveFixtureAdversarialTests {
    typealias Fixture = MigrationFixtureAdversarialTests

    @Test(
        "A database file version 1 wrote takes the linked save as it is: the swap, the log dropped, its schema kept"
    )
    func save_onTheVersionOneFixture_needsNoMigration() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let queue = try Fixture.copy(in: directory)
        // The migrations this build knows, none of them S3's, bring the file up to date; the save follows.
        try LedgerDatabase.migrator.migrate(queue)
        let schema = try await queue.read { try Fixture.schema($0) }
        let stores = LedgerStores(queue, deviceID: S3Kit.device, now: { S3Kit.now })
        let program = try #require(try await stores.programs.active())
        let slot = try #require(program.days.first?.slots.first)
        let replacement = try #require(try await stores.exercises.all().first { $0.id != slot.exerciseID })
        var workout = LinkedFixture.workout(1, ofProgram: nil, updates: [slot.id: replacement.id])
        workout.source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[0].id)
        _ = try await stores.events.append(LinkedFixture.log(of: workout, count: 3))
        var missed = slot
        missed.misses = [0, 1]
        #expect(try await stores.workouts.materialize(workout, slotUpdates: [missed], droppingLog: true))
        let stored = try await stores.programs.active()?.days.first?.slots.first
        #expect(stored?.exerciseID == replacement.id && stored?.misses == [0, 1])
        #expect(try await stores.events.envelopes(for: workout.id).isEmpty)
        #expect(try await stores.workouts.workout(id: workout.id) != nil)
        let isSameSchema = try await queue.read { try Fixture.schema($0) } == schema
        #expect(isSameSchema, "the save changed the fixture's schema")
        let fresh = try await LedgerDatabase.inMemory().read { try Fixture.schema($0) }
        #expect(schema == fresh, "the version-1 schema is no longer what a new database gets")
    }
}
