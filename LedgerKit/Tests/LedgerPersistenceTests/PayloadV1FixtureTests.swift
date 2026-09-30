import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// Review SF1 (orchestrator decision, 2026-09-30): the committed version-1 payloads in
/// `Fixtures/payload-v001/` still decode, with version 1, to their literals in `PayloadV1`, and version 1
/// is still what the codecs write. **A failure here is never fixed by editing a fixture**: it means a
/// LedgerDomain `Codable` change altered version 1, so it ships as payload version 2 (`PayloadV1`).
@Suite("Payload version 1 · golden fixtures", .tags(.persistence))
struct PayloadV1FixtureTests {
    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/payload-v001"
        ))
        return try Data(contentsOf: url)
    }

    /// `data` parsed as a JSON object, so two encodings compare by content, not by layout.
    static func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test(
        "Each committed version-1 envelope decodes to its literal, and is still what encode writes",
        arguments: PayloadV1.fixtures
    )
    func envelope_decodesToItsLiteral(_ fixture: PayloadV1.Fixture) throws {
        let committed = try Self.fixture(fixture.file)
        let decoded = try EnvelopeCodec.decode(committed, version: 1)
        #expect(PayloadV1.identical(decoded, fixture.envelope), "\(decoded)")
        #expect(try Self.object(EnvelopeCodec.encode(fixture.envelope)) == Self.object(committed))
    }

    @Test("Every WorkoutEvent case has a version-1 fixture")
    func everyEventCase_hasAFixture() {
        #expect(Set(PayloadV1.fixtures.map { PayloadV1.caseName($0.envelope.event) }) == PayloadV1.allCaseNames)
    }

    @Test("The committed version-1 settings payload decodes to its literal, and is still what encode writes")
    func settings_decodesToItsLiteral() throws {
        let committed = try Self.fixture("settings")
        #expect(try SettingsCodec.decode(committed, version: 1) == PayloadV1.settings)
        #expect(try Self.object(SettingsCodec.encode(PayloadV1.settings)) == Self.object(committed))
    }
}
