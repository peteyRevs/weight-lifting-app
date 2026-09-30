import Foundation
@testable import LedgerDomain
import Testing

@Suite("Settings", .tags(.domain))
struct SettingsTests {
    @Test("Defaults match the prototype: lb, 90 s rest, plate math, auto rest and buzz on")
    func default_matchesPrototype() {
        let settings = Settings.default
        #expect(settings.units == .lb)
        #expect(settings.defaultRest.seconds == 90)
        #expect(settings.plateMathEnabled)
        #expect(settings.autoRest)
        #expect(settings.watchBuzz)
        #expect(settings.weekStart == .monday)
        #expect(settings.plateInventory == [.lb: .standard(.lb), .kg: .standard(.kg)])
    }

    @Test("Settings round-trip through JSON with unit-keyed inventories")
    func codable_roundTrip_preservesValue() throws {
        var settings = Settings.default
        settings.units = .kg
        settings.weekStart = .sunday
        let data = try JSONEncoder().encode(settings)
        #expect(try Fixtures.json(settings).contains(#""plateInventory":{"#))
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }

    @Test("A missing key decodes to its default, so settings stored before a field existed still load (F05)")
    func decoding_missingKeys_takeTheirDefaults() throws {
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)) == .default)
        var settings = Settings.default
        settings.units = .kg
        settings.autoRest = false
        let json = #"{"units":"kg","autoRest":false}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(json.utf8)) == settings)
    }

    @Test("A key that is present must still be valid: an unknown unit or a 17 s rest is refused")
    func decoding_invalidPresentKey_throws() {
        for json in [#"{"units":"stone"}"#, #"{"defaultRest":17}"#] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Settings.self, from: Data(json.utf8)) }
        }
    }
}
