import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `ProbedProgramRepository.update` (F11 S3 criterion 9): the probe passes an update on, counts it, holds it
/// before it reaches the store and can make it fail. This is how the builder's store test (S13) holds its
/// first write while more edits arrive, so each case runs over the in-memory stores, which that test uses,
/// and over the database.
@Suite("ProbedProgramRepository · update", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProbedProgramRepositoryTests {
    typealias Stores = ProgramUpdateInterleavingTests.Stores

    /// Probed stores over `stores`, holding the contract program, and the unprobed program store to read.
    struct Subject {
        let probed: ProbedStores
        let base: any ProgramRepository
        let program: Program

        var probe: StoreProbe {
            probed.probe
        }

        init(on stores: Stores) async throws {
            let side = try await stores.side()
            probed = ProbedStores(events: side.events, workouts: side.workouts, programs: side.programs)
            base = side.programs
            program = try ProgramRepositoryContract.program()
            try await base.save(program)
        }

        /// The stored program's name, read past the probe.
        func storedName() async throws -> String? {
            try await base.active()?.name
        }

        func updates() async -> Int {
            await probe.calls.count { $0 == .updateProgram }
        }
    }

    static func adding(_ suffix: String) -> @Sendable (Program) -> Program {
        { stored in
            var changed = stored
            changed.name += suffix
            return changed
        }
    }

    @Test(
        "An update goes through the probe to the store: recorded once, stored, and answered",
        arguments: Stores.allCases
    )
    func update_isPassedOn_andCounted(stores: Stores) async throws {
        let subject = try await Subject(on: stores)
        let returned = try await subject.probed.programs.update(subject.program.id, Self.adding(" A"))
        #expect(returned.name == "Block 0 A")
        #expect(try await subject.storedName() == "Block 0 A")
        #expect(await subject.probe.calls == [.updateProgram])
    }

    @Test(
        "A held update stores nothing until it is released; the next one is then a second write",
        arguments: Stores.allCases
    )
    func heldUpdate_storesNothingUntilReleased(stores: Stores) async throws {
        let subject = try await Subject(on: stores)
        await subject.probe.hold(.updateProgram)
        let first = Task { try await subject.probed.programs.update(subject.program.id, Self.adding(" A")) }
        try await subject.probe.waitUntilHeld()
        #expect(try await subject.storedName() == "Block 0")
        #expect(await subject.updates() == 1)
        await subject.probe.release()
        #expect(try await first.value.name == "Block 0 A")
        // Sent after the first returned, the next change meets what the first stored.
        #expect(try await subject.probed.programs.update(subject.program.id, Self.adding(" B")).name == "Block 0 A B")
        #expect(await subject.updates() == 2)
    }

    @Test(
        "A held update whose task is cancelled stores nothing when released, and throws CancellationError",
        arguments: Stores.allCases
    )
    func heldUpdate_cancelled_storesNothing(stores: Stores) async throws {
        let subject = try await Subject(on: stores)
        await subject.probe.hold(.updateProgram)
        let write = Task { try await subject.probed.programs.update(subject.program.id, Self.adding(" A")) }
        try await subject.probe.waitUntilHeld()
        write.cancel()
        await subject.probe.release()
        await #expect(throws: CancellationError.self) { _ = try await write.value }
        #expect(try await subject.storedName() == "Block 0")
    }

    @Test(
        "An update made to fail throws the refusal: before the store, nothing is stored; after it, the change is",
        arguments: Stores.allCases
    )
    func failedUpdate_throwsTheRefusal(stores: Stores) async throws {
        let subject = try await Subject(on: stores)
        let refusal = StoreProbe.Refusal(call: .updateProgram)
        await subject.probe.fail(.updateProgram)
        await #expect(throws: refusal) {
            _ = try await subject.probed.programs.update(subject.program.id, Self.adding(" A"))
        }
        #expect(try await subject.storedName() == "Block 0")
        // The answer lost: the store did what was asked, and the caller hears a failure.
        await subject.probe.fail(.updateProgram, afterStoring: true)
        await #expect(throws: refusal) {
            _ = try await subject.probed.programs.update(subject.program.id, Self.adding(" B"))
        }
        #expect(try await subject.storedName() == "Block 0 B")
    }
}
