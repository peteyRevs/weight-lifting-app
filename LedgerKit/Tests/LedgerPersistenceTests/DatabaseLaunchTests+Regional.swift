import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F14 S1, N3: the phone's settings step seeds the region's settings where none are stored; the watch's seeds none.
extension DatabaseLaunchTests {
    nonisolated static let refuseSettings =
        "CREATE TRIGGER refuse_settings BEFORE INSERT ON settings BEGIN SELECT RAISE(ABORT, 'full'); END"

    @Test("F14 N3. The phone's settings step seeds the regional settings where none are stored, once, then loads them")
    func regional_seededOnce_thenLoaded() async throws {
        let subject = Subject(regionalSettings: Self.kilograms)
        defer { subject.remove() }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
        #expect(subject.launch.settings == Self.kilograms)
        var changed = Self.kilograms
        changed.weekStart = .wednesday
        let stores = try #require(subject.launch.stores)
        try await stores.settings.save(changed)
        let next = Subject(regionalSettings: Self.kilograms, in: subject.directory)
        next.launch.open()
        await next.launch.resume(isForeground: true)
        #expect(next.launch.settings == changed, "a second launch seeds nothing over the saved settings")
    }

    @Test("F14 N3. A launch given no regional settings (the watch) seeds nothing: the settings stay unstored")
    func noRegional_seedsNothing() async throws {
        let subject = Subject()
        defer { subject.remove() }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        #expect(subject.launch.settings == .default)
        let rows = try await #require(subject.launch.stores).queue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings")
        }
        #expect(rows == 0)
    }

    @Test("F14 N3. A seed that fails is logged, the step goes on, and the settings are what load gives")
    func regionalSeedFailure_carriesOn() async throws {
        let subject = Subject(regionalSettings: Self.kilograms)
        defer { subject.remove() }
        try subject.arrange { try $0.execute(sql: Self.refuseSettings) }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
        #expect(subject.launch.settings == .default)
    }
}
