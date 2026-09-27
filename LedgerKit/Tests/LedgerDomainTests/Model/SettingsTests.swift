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
    func codable_roundTrips() throws {
        var settings = Settings.default
        settings.units = .kg
        settings.weekStart = .sunday
        let data = try JSONEncoder().encode(settings)
        #expect(try Fixtures.json(settings).contains(#""plateInventory":{"#))
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }
}
