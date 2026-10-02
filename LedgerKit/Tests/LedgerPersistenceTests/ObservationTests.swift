import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// The repositories' `ValueObservation` streams (`observeAll`, `observeActive`): the current value first, then
/// one value per change that alters it, and none for a write that does not. `LedgerPersistenceTests` runs in the
/// PR-Watch plan too, so these emissions are checked on the watch simulator as well (F05 risk
/// "ValueObservation on watchOS"). S3 adds `observeRecent` (criterion 10).
@Suite("Repository observation", .tags(.persistence), .timeLimit(.minutes(1)))
struct ObservationTests {
    /// Every value `observation` emits, in order. The repositories' streams keep only the newest value, so a
    /// spurious emission there would be replaced by the next real one before a test read it (review N4); this
    /// stream drops none, so a test sees one.
    static func everyValue<Value: Equatable & Sendable>(
        _ observation: DistinctObservation<Value>,
        in queue: DatabaseQueue
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let cancellable = observation.start(
                in: queue,
                scheduling: .async(onQueue: DispatchQueue(label: "ObservationTests"))
            ) { _ in
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    @Test("observeAll's observation emits the catalog, then after a custom save, and none for a no-op write")
    func observeAll_emitsOnChange_only() async throws {
        let repositories = try Repositories()
        let catalog = Seeders.catalog(count: 3, version: 1).exercises
        try await repositories.exercises.seedIfNeeded(catalog, version: 1)
        let observation = GRDBExerciseRepository.allObservation()
        var values = Self.everyValue(observation, in: repositories.queue).makeAsyncIterator()
        #expect(await values.next().map(Set.init) == Set(catalog))
        try await repositories.execute("UPDATE exercise SET name = name") // a write that changes no value
        try await repositories.exercises.save(ExerciseRepositoryContract.landmine)
        #expect(await values.next().map(Set.init) == Set(catalog + [ExerciseRepositoryContract.landmine]))
    }

    @Test("observeActive's observation emits nil, the program, each edit and nil after delete; none for a no-op write")
    func observeActive_emitsEachChange_only() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let programs = repositories.programs
        let program = try ProgramRepositoryContract.program()
        let edited = try ProgramRepositoryContract.edited(program)
        let observation = GRDBProgramRepository.activeObservation()
        var values = Self.everyValue(observation, in: repositories.queue).makeAsyncIterator()
        #expect(await values.next() == .some(nil))
        try await programs.save(program)
        #expect(await values.next() == program)
        try await repositories.execute("UPDATE slot SET sets = sets") // a write that changes no value
        try await programs.save(edited)
        #expect(await values.next() == edited)
        try await programs.delete(program.id)
        #expect(await values.next() == .some(nil))
    }

    @Test("observeActive follows setActive to another program, and ignores an inactive one's edits")
    func observeActive_followsSetActive() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        let first = try ProgramRepositoryContract.program(number: 1, isActive: true)
        let second = try ProgramRepositoryContract.program(number: 2, isActive: false)
        try await programs.save(first)
        var values = programs.observeActive().makeAsyncIterator()
        #expect(await values.next() == first)
        try await programs.save(second) // an inactive program: the active one is unchanged
        try await programs.setActive(second.id)
        var active = second
        active.isActive = true
        #expect(await values.next() == active)
    }
}
