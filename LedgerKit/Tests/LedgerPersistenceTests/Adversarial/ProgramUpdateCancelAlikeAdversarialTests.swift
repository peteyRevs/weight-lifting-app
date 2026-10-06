import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F11 S3 adversarial round 2, criterion 12: the in-memory store cancels as the database does. A task cancelled
/// inside its change, whatever the change then does (returns an edit, the program as it was, each result a
/// store refuses, or throws), ends with the same error on both stores, and with nothing written on either.
@Suite(
    "Adversarial F11 S3 · a cancelled update ends alike on both stores",
    .tags(.persistence),
    .timeLimit(.minutes(1))
)
struct ProgramUpdateCancelAlikeAdversarialTests {
    typealias Call = Task<Program, any Error>

    /// How an update of program 1 ends when its task is cancelled inside the change, before `result` is computed;
    /// and what was written, if anything.
    static func ending(
        on stores: LinkedStores,
        _ result: @escaping @Sendable (Program) throws -> Program
    ) async throws -> String {
        let before = try await UpdateSnapshot(stores)
        let handle = Mutex<Call?>(nil)
        let (ready, start) = AsyncStream<Void>.makeStream()
        let call = Call {
            for await _ in ready {
                break
            }
            return try await stores.programs.update(UpdateKit.one) { program in
                handle.withLock { $0?.cancel() }
                return try result(program)
            }
        }
        handle.withLock { $0 = call }
        start.yield()
        var outcome = "returned"
        if case let .failure(error) = await call.result {
            outcome = "\(error)"
        }
        let written = try await UpdateSnapshot(stores).difference(from: before)
        return String(outcome.prefix(90)) + (written.map { ", written: \($0)" } ?? "")
    }

    @Test("Cancelled inside the change, every kind of result ends alike on the database and in memory")
    func cancelledInsideTheChange_everyResult_sameEndingOnBothStores() async throws {
        var results = UpdateRefusal.all.map { ($0.name, $0.result) }
        results += UpdateRoutes.unchanged.map { ("unchanged, \($0.name)", $0.change) }
        results += UpdateEdit.all.map { ("edit, \($0.name)", $0.change) }
        var differing: [String] = []
        for (name, result) in results {
            let database = try await LinkedStores.make(.database)
            let memory = try await LinkedStores.make(.memory)
            let (first, second) = try await (Self.ending(on: database, result), Self.ending(on: memory, result))
            if first != second {
                differing.append("\(name): database \(first); memory \(second)")
            }
        }
        #expect(
            differing.isEmpty,
            "\(differing.count) of \(results.count): \(differing.prefix(8).joined(separator: " | "))"
        )
    }

    @Test("Cancelled, an update of a program that is not stored ends alike on both stores")
    func cancelled_missingProgram_sameEndingOnBothStores() async throws {
        var endings: [String] = []
        for kind in LinkedStores.Kind.allCases {
            let stores = try await LinkedStores.make(kind)
            try await stores.programs.delete(UpdateKit.two)
            for id in [S2Kit.programID(404), UpdateKit.two] {
                let call = Call {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await stores.programs.update(id) { $0 }
                }
                if case let .failure(error) = await call.result {
                    endings.append("\(error)".prefix(40).description)
                } else {
                    endings.append("returned")
                }
            }
        }
        #expect(Set(endings).count == 1, "\(endings)")
    }

    @Test("Held at the probe and cancelled there, an update throws CancellationError on both stores, nothing stored")
    func heldAtTheProbeAndCancelled_sameEndingOnBothStores() async throws {
        var endings: [String] = []
        for kind in LinkedStores.Kind.allCases {
            let stores = try await LinkedStores.make(kind)
            let probed = ProgramUpdateProbeAdversarialTests.probed(stores)
            let before = try await UpdateSnapshot(stores)
            await probed.probe.hold(.updateProgram)
            let held = Call { try await probed.programs.update(UpdateKit.one, UpdateKit.increment) }
            try await probed.probe.waitUntilHeld()
            held.cancel()
            await probed.probe.release()
            let wasCancelled = await ProgramUpdateCancelAdversarialTests.wasCancelled(held)
            let written = try await UpdateSnapshot(stores).difference(from: before)
            endings.append("\(kind): \(wasCancelled ? "cancelled" : "not cancelled"), \(written ?? "nothing written")")
        }
        #expect(endings == ["database: cancelled, nothing written", "memory: cancelled, nothing written"], "\(endings)")
    }
}
