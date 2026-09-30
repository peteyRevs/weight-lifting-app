import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 2 (close-out): the fix round's tolerant `Settings.init(from:)` and the settings
/// row's `payload_version`, through `GRDBSettingsRepository`. The notes promise: a missing key takes its
/// default; a key that is present must be valid, so a wrong type fails the whole load and the row is kept; a
/// row in a version this app does not know fails load by name and is kept.
@Suite("Adversarial S1 round 2 · tolerant settings", .tags(.persistence), .timeLimit(.minutes(1)))
struct SettingsDecodingAdversarialTests {
    /// One of version 1's keys, with a JSON value of the wrong type for it.
    struct Key: Sendable, CustomStringConvertible {
        let description: String
        let wrongType: String

        /// `settings` with this key's field set to its `Settings.default` value.
        func defaulted(_ settings: Settings) -> Settings {
            var result = settings
            let fallback = Settings.default
            switch description {
            case "units": result.units = fallback.units
            case "defaultRest": result.defaultRest = fallback.defaultRest
            case "plateMathEnabled": result.plateMathEnabled = fallback.plateMathEnabled
            case "autoRest": result.autoRest = fallback.autoRest
            case "watchBuzz": result.watchBuzz = fallback.watchBuzz
            case "weekStart": result.weekStart = fallback.weekStart
            default: result.plateInventory = fallback.plateInventory
            }
            return result
        }
    }

    static let keys = [
        Key(description: "units", wrongType: "true"),
        Key(description: "defaultRest", wrongType: #""90""#),
        Key(description: "plateMathEnabled", wrongType: #""yes""#),
        Key(description: "autoRest", wrongType: "[]"),
        Key(description: "watchBuzz", wrongType: "{}"),
        Key(description: "weekStart", wrongType: #""monday""#),
        Key(description: "plateInventory", wrongType: #""none""#)
    ]

    static let custom = SettingsRepositoryTests.custom

    /// A repository whose row holds `custom`, then `edit` applied to its payload in SQL.
    static func repository(editing edit: String? = nil) async throws -> (GRDBSettingsRepository, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue, now: { EventBuilders.start })
        try await repository.save(custom)
        if let edit {
            try await queue.write { try $0.execute(sql: "UPDATE settings SET \(edit)") }
        }
        return (repository, queue)
    }

    static func row(_ queue: DatabaseQueue) async throws -> String? {
        try await queue.read { database in
            try String.fetchOne(database, sql: "SELECT quote(payload_version) || ',' || quote(payload) FROM settings")
        }
    }

    @Test("Version 1's keys are exactly these seven, so a renamed key cannot pass as a missing one")
    func version1_hasExactlyTheseKeys() throws {
        let object = try JSONSerialization.jsonObject(with: SettingsCodec.encode(Self.custom)) as? [String: Any]
        #expect(Set(object?.keys.map(\.self) ?? []) == Set(Self.keys.map(\.description)))
    }

    @Test("A row missing one key loads with that field's default and every other field as saved", arguments: keys)
    func oneMissingKey_takesItsDefault(_ key: Key) async throws {
        let (repository, _) = try await Self.repository(editing: "payload = json_remove(payload, '$.\(key)')")
        #expect(try await repository.load() == key.defaulted(Self.custom))
        var values = repository.observe().makeAsyncIterator()
        #expect(await values.next() == key.defaulted(Self.custom))
    }

    @Test("Unknown keys, at the top and inside an inventory, are ignored")
    func unknownKeys_areIgnored() async throws {
        let (repository, _) = try await Self.repository(editing: """
        payload = json_set(payload, '$.iCloudEnabled', json('true'), '$.future', json('{"a":[1,null]}'),
            '$.plateInventory.kg.colour', 'red')
        """)
        #expect(try await repository.load() == Self.custom)
    }

    @Test("A wrong type in one key fails the whole load, as the notes promise, and the row is kept", arguments: keys)
    func wrongTypeInOneKey_failsTheLoad_andKeepsTheRow(_ key: Key) async throws {
        let edit = "payload = json_set(payload, '$.\(key)', json('\(key.wrongType)'))"
        let (repository, queue) = try await Self.repository(editing: edit)
        let before = try await Self.row(queue)
        await #expect(throws: DecodingError.self) { try await repository.load() }
        #expect(try await Self.row(queue) == before)
    }

    @Test("(documents) A key holding null is treated as missing: it takes its default")
    func nullValues_takeTheirDefaults() async throws {
        let nulls = Self.keys.map { "'$.\($0)', json('null')" }.joined(separator: ", ")
        let (repository, _) = try await Self.repository(editing: "payload = json_set(payload, \(nulls))")
        #expect(try await repository.load() == .default)
    }

    @Test(
        "An unknown version fails load and observe by name and is kept; a save replaces it with version 1",
        arguments: [0, -1, 2, 7] + (Int.bitWidth == 64 ? [Int(Int64.max)] : [])
    )
    func unknownVersion_failsByName_andASaveWritesVersion1(_ version: Int) async throws {
        let (repository, queue) = try await Self.repository(editing: "payload_version = \(version)")
        let kept = try await Self.row(queue)
        await #expect(throws: LedgerPersistenceError.unknownPayloadVersion(version)) { try await repository.load() }
        var emitted = 0
        for await _ in repository.observe() {
            emitted += 1
        }
        #expect(emitted == 0)
        #expect(try await Self.row(queue) == kept)
        var changed = Self.custom
        changed.autoRest = true
        try await repository.save(changed)
        #expect(try await Self.row(queue)?.hasPrefix("1,") == true)
        #expect(try await repository.load() == changed)
    }
}

#if os(macOS)
    extension SettingsDecodingAdversarialTests {
        /// Test findings round 2, finding 4: `fetch` reads the row with GRDB's trapping subscripts, so a
        /// damaged column that the event store reads as "unreadable" traps here. Exit test: host only.
        @Test("A damaged settings row (a non-integer version, or bytes that are not UTF-8) fails load; it never traps")
        func damagedRow_failsLoad_neverTraps() async {
            await #expect(processExitsWith: .success) {
                let damages = ["payload_version = 'two'", "payload_version = x'01'", "payload = x'FFFE7B7D'"]
                for damage in damages {
                    let (repository, _) = try await SettingsDecodingAdversarialTests.repository(editing: damage)
                    if await (try? repository.load()) != nil {
                        exit(1)
                    }
                    for await _ in repository.observe() {
                        exit(2)
                    }
                }
            }
        }
    }
#endif
