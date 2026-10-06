@testable import FeatureToday
import Foundation
import LedgerTestSupport
import Testing

/// Round 2, criterion 14: the spoken volume line is copy, "one key per unit for the line with a change and one
/// for the line without"; and the catalog and the copy files still hold one another's keys, by count.
nonisolated extension TodayPurityAdversarialTests {
    /// The keys of `Resources/Localizable.xcstrings`, read as JSON.
    static func catalogKeys() throws -> [String] {
        let data = try Data(contentsOf: Support.sources.appending(path: "Resources/Localizable.xcstrings"))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any]).keys.sorted()
    }

    @Test("The catalog holds as many keys as the copy files hold lookups, and the six the rulings add")
    func catalog_holdsTheRulingsKeys() throws {
        let keys = try Self.catalogKeys()
        let copy = try Self.sources().filter { $0.name.hasPrefix("TodayCopy") }
        let calls = copy.flatMap { Self.lookups(in: $0.lines.joined(separator: "\n")) }
        #expect(keys.count == calls.count)
        let spoken = keys.filter { $0.contains("moved this week") }
        #expect(spoken.count == 4, "\(spoken)")
        #expect(spoken.count { $0.contains(" lb moved this week") } == 2)
        #expect(spoken.count { $0.contains(" kg moved this week") } == 2)
        #expect(spoken.count { $0.contains("from last week") } == 2)
        #expect(keys.count { $0.hasPrefix("Your block starts on ") } == 1)
        #expect(keys.count { $0.hasSuffix("No sessions are left in this block.") } == 1)
        #expect(keys.count { $0.hasSuffix("This is the last week of the block.") } == 1)
        let named = keys.filter { $0.lowercased().contains("ledger") }
        #expect(named == [])
    }
}
