import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Close-out finding 4 (orchestrator decision, fix round 2): a damaged settings column makes `load()` throw
/// `LedgerPersistenceError.malformedColumn` and ends `observe()`. It never traps, and never falls back to the
/// defaults silently, which a later save would write over the lifter's real settings.
@Suite("GRDBSettingsRepository · damaged row", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedSettingsRowTests {
    /// A damage in SQL, and the column it names.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        let column: String
    }

    /// (A number in `payload` is no damage of this kind: the column's `TEXT` affinity stores it as text, and
    /// load fails with `DecodingError`, as for any invalid JSON.)
    static let damages = [
        Damage(description: "payload_version = 'two'", column: "settings.payload_version"),
        Damage(description: "payload_version = x'01'", column: "settings.payload_version"),
        Damage(description: "payload = x'FFFE7B7D'", column: "settings.payload"),
        Damage(description: "payload = x'80'", column: "settings.payload")
    ]

    @Test("A damaged column fails load by name and ends observe; the row is kept", arguments: damages)
    func damagedColumn_failsLoadByName_andEndsObserve(_ damage: Damage) async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue, now: { EventBuilders.start })
        try await repository.save(SettingsRepositoryTests.custom)
        try await queue.write { try $0.execute(sql: "UPDATE settings SET \(damage)") }
        let row = "SELECT quote(payload_version) || ',' || quote(payload) FROM settings"
        let before = try await queue.read { try String.fetchOne($0, sql: row) }
        await #expect(throws: LedgerPersistenceError.malformedColumn(damage.column)) { try await repository.load() }
        var emitted = 0
        for await _ in repository.observe() {
            emitted += 1
        }
        #expect(emitted == 0)
        #expect(try await queue.read { try String.fetchOne($0, sql: row) } == before)
    }
}
