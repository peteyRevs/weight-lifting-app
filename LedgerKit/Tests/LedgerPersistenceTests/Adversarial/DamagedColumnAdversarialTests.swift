import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 3 (close-out): fix round 2's `malformedColumn` (close-out finding 4). Every damaged
/// shape of the settings row's two columns makes `load()` throw and `observe()` end, never trap, never return
/// the defaults, and the row is kept. An observation that is running when the row is damaged ends too.
@Suite("Adversarial S1 round 3 · damaged settings columns", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedColumnAdversarialTests {
    /// A `SET` clause and the error `load()` must throw for it.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        /// `nil` for a `DecodingError`: UTF-8 text that is not valid settings JSON.
        let error: LedgerPersistenceError?

        func matches(_ thrown: any Error) -> Bool {
            if let error {
                return thrown as? LedgerPersistenceError == error
            }
            return thrown is DecodingError
        }
    }

    static let version = LedgerPersistenceError.malformedColumn("settings.payload_version")
    static let payload = LedgerPersistenceError.malformedColumn("settings.payload")
    static let invalidJSON: LedgerPersistenceError? = nil

    static let damages = [
        Damage(description: "payload_version = 1e30", error: version),
        Damage(description: "payload_version = -1e30", error: version),
        Damage(description: "payload_version = 9.3e18", error: version),
        Damage(description: "payload_version = x''", error: version),
        Damage(description: "payload_version = ''", error: version),
        Damage(description: "payload_version = '1 one'", error: version),
        Damage(description: "payload_version = 2.5", error: LedgerPersistenceError.unknownPayloadVersion(2)),
        Damage(description: "payload = x'C0'", error: payload),
        Damage(description: "payload = x'EDA080'", error: payload),
        Damage(description: "payload = x'7B2275'", error: invalidJSON), // `{"u`: UTF-8, not JSON
        Damage(description: "payload = x''", error: invalidJSON),
        Damage(description: "payload = 'null'", error: invalidJSON),
        Damage(description: "payload = 7", error: invalidJSON),
        Damage(description: "payload = x'7B7D00'", error: invalidJSON)
    ]

    static func damaged(_ damage: Damage) async throws -> (GRDBSettingsRepository, DatabaseQueue) {
        let (repository, queue) = try SettingsRepositoryTests.repository()
        try await repository.save(SettingsRepositoryTests.custom)
        try await queue.write { try $0.execute(sql: "UPDATE settings SET \(damage)") }
        return (repository, queue)
    }

    static func row(_ queue: DatabaseQueue) async throws -> String? {
        try await queue.read { database in
            try String.fetchOne(database, sql: "SELECT quote(payload_version) || ',' || quote(payload) FROM settings")
        }
    }

    @Test(
        "Each damaged column fails load with its error and ends observe with no value; the row is kept",
        arguments: damages
    )
    func damagedColumn_failsLoad_endsObserve_keepsRow(_ damage: Damage) async throws {
        let (repository, queue) = try await Self.damaged(damage)
        let before = try await Self.row(queue)
        do {
            let loaded = try await repository.load()
            Issue.record("loaded \(loaded == .default ? "the defaults" : "\(loaded)") from \(damage)")
        } catch {
            #expect(damage.matches(error), "\(damage): threw \(error)")
        }
        var emitted: [Settings] = []
        for await settings in repository.observe() {
            emitted.append(settings)
        }
        #expect(emitted.isEmpty, "\(damage)")
        #expect(try await Self.row(queue) == before, "\(damage)")
    }

    @Test("An observation that is running when the row is damaged ends, and emits no defaults", arguments: [
        "payload_version = 'two'", "payload = x'FFFE7B7D'", "payload_version = 3"
    ])
    func runningObservation_endsWhenTheRowIsDamaged(_ damage: String) async throws {
        let (repository, queue) = try SettingsRepositoryTests.repository()
        try await repository.save(SettingsRepositoryTests.custom)
        var iterator = repository.observe().makeAsyncIterator()
        #expect(await iterator.next() == SettingsRepositoryTests.custom)
        try await queue.write { try $0.execute(sql: "UPDATE settings SET \(damage)") }
        #expect(await iterator.next() == nil, "\(damage)")
    }

    @Test("(documents) A fractional REAL version is truncated by GRDB and reads as that integer version")
    func fractionalVersion_isTruncated() async throws {
        let (repository, queue) = try SettingsRepositoryTests.repository()
        try await repository.save(SettingsRepositoryTests.custom)
        try await queue.write { try $0.execute(sql: "UPDATE settings SET payload_version = 1.5") }
        #expect(try await repository.load() == SettingsRepositoryTests.custom)
    }
}
