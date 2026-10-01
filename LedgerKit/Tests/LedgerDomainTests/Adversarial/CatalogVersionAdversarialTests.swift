import CryptoKit
import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Criteria 7 and 8: the version history pins the bundled file, and the seed fixture is usable.
@Suite("Exercise catalog version and seed fixture (adversarial)", .tags(.domain))
struct CatalogVersionAdversarialTests {
    /// The `<version> <sha256>` lines of `catalog.version.sha`, comments and blanks dropped.
    static func history() throws -> [(version: Int, sha: String)] {
        let data = try ExerciseCatalog.resource("catalog.version", withExtension: "sha")
        let text = try #require(String(bytes: data, encoding: .utf8))
        return try text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let match = try #require(line.wholeMatch(of: /([1-9][0-9]*) ([0-9a-f]{64})/), "bad line: \(line)")
                return try (#require(Int(match.output.1)), String(match.output.2))
            }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension CatalogVersionAdversarialTests {
    @Test("The history's last line is ExerciseCatalog.version and the SHA-256 of the bundled file (criterion 7).")
    func history_lastLinePinsTheFile() throws {
        let history = try Self.history()
        let last = try #require(history.last)
        #expect(last.version == ExerciseCatalog.version)
        #expect(try last.sha == Self.sha256(CatalogUnderTest.data()))
    }

    @Test("History versions start at 1 or more and strictly rise; no SHA repeats (a bump always changes the file).")
    func history_risesStrictly() throws {
        let history = try Self.history()
        #expect(!history.isEmpty)
        for (earlier, later) in zip(history, history.dropFirst()) {
            #expect(later.version > earlier.version, "\(earlier.version) then \(later.version)")
        }
        #expect(Set(history.map(\.sha)).count == history.count)
    }

    @Test("A one-byte change to the file changes the SHA the test compares, so an unbumped edit fails.")
    func sha_detectsAOneByteEdit() throws {
        var data = try CatalogUnderTest.data()
        let original = Self.sha256(data)
        data.append(0x0A)
        #expect(Self.sha256(data) != original)
        #expect(try Self.history().last?.sha != Self.sha256(data))
    }

    @Test("The JSON stays within the 200 KB budget (non-functional).")
    func json_withinBudget() throws {
        #expect(try CatalogUnderTest.data().count <= 200 * 1024)
    }
}

// MARK: - Criterion 8: the seed fixture

extension CatalogVersionAdversarialTests {
    @Test("The fixture's base is the bundled catalog; the upgrade is one version up and only appends.")
    func fixture_baseAndUpgrade() throws {
        let base = try CatalogSeedFixture.base()
        let upgrade = try CatalogSeedFixture.upgrade()
        #expect(base.version == ExerciseCatalog.version)
        #expect(try base.exercises == CatalogUnderTest.exercises())
        #expect(upgrade.version == base.version + 1)
        #expect(Array(upgrade.exercises.prefix(base.exercises.count)) == base.exercises)
        #expect(upgrade.exercises.count == base.exercises.count + 2)
        #expect(try CatalogSeedFixture.base() == base) // deterministic across calls
    }

    @Test("Fixture names and ids: custom and added are new to the catalog; clash is custom in another case.")
    func fixture_namesAndIDs() throws {
        let entries = try CatalogUnderTest.entriesDecoded()
        let names = Set(entries.flatMap { [$0.name] + $0.aliases }.map { $0.lowercased() })
        let ids = Set(entries.map(\.id))
        let custom = CatalogSeedFixture.custom
        let added = CatalogSeedFixture.added
        let clash = CatalogSeedFixture.clash
        #expect(!names.contains(custom.name.lowercased()))
        #expect(!names.contains(added.name.lowercased()))
        #expect(clash.name != custom.name && clash.name.lowercased() == custom.name.lowercased())
        #expect(custom.isCustom && !added.isCustom && !clash.isCustom)
        #expect(Set([custom.id, added.id, clash.id]).count == 3)
        #expect(ids.isDisjoint(with: [custom.id, added.id, clash.id]))
    }
}
