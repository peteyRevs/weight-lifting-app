import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import Testing

/// F14 S1a, G2: `seedIfAbsent` and the launch's seed (N3) under races, double launches and an install that
/// predates F14.
@Suite("Settings seed, adversarial", .tags(.persistence), .timeLimit(.minutes(1)))
struct SettingsSeedAdversarialTests {
    static var kilograms: Settings {
        var settings = Settings.default
        settings.units = .kg
        settings.weekStart = .sunday
        return settings
    }

    static var lifters: Settings {
        var settings = Settings.default
        settings.weekStart = .thursday
        settings.autoRest = false
        return settings
    }

    @Test("A seed racing the lifter's save never wins over it, whichever runs first", arguments: 0 ..< 20)
    func seedRacingASave_neverOverwritesIt(round: Int) async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue)
        async let seeded: Void = repository.seedIfAbsent(Self.kilograms)
        async let saved: Void = repository.save(Self.lifters)
        _ = try await (seeded, saved)
        let kept = try await repository.load() == Self.lifters
        #expect(kept, "round \(round)")
    }

    @Test("Two seeds at once leave one row, holding one of them whole", arguments: 0 ..< 20)
    func twoSeeds_leaveOneWholeRow(round: Int) async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue)
        async let first: Void = repository.seedIfAbsent(Self.kilograms)
        async let second: Void = repository.seedIfAbsent(Self.lifters)
        _ = try await (first, second)
        let rows = try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") }
        #expect(rows == 1)
        let stored = try await repository.load()
        let whole = stored == Self.kilograms || stored == Self.lifters
        #expect(whole, "round \(round)")
    }

    @Test("A seed is observed once; a second seed is not observed")
    func seed_observedOnce() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue)
        var values = repository.observe().makeAsyncIterator()
        let first = await values.next() == .default
        try await repository.seedIfAbsent(Self.kilograms)
        let seeded = await values.next() == Self.kilograms
        try await repository.seedIfAbsent(Self.lifters)
        try await repository.save(Self.lifters)
        let saved = await values.next() == Self.lifters
        #expect(first)
        #expect(seeded)
        #expect(saved, "the second seed changed nothing to observe")
    }

    /// F14-S1-5. Before F14 nothing saved settings (the plan's C1), so every install made before it has no
    /// settings row and runs on `Settings.default` (pounds, Monday weeks), with a program whose block copied them
    /// (C2). The first launch after the update finds no row and seeds the region's settings, as for a new
    /// install: a lifter in Germany is switched to kilograms and a lifter in the US to Sunday weeks, unasked.
    @MainActor
    @Test("F14-S1-5. An install made before F14 (a program, no settings row) keeps the settings it ran on")
    func installBeforeF14_keepsItsSettings() async throws {
        let before = DatabaseLaunchTests.Subject(regionalSettings: nil)
        defer { before.remove() }
        before.launch.open()
        await before.launch.resume(isForeground: true)
        let stores = try #require(before.launch.stores)
        try await stores.programs.save(Fixtures.seedProgram())
        let onboarded = try await stores.programs.active() != nil
        #expect(onboarded)

        let after = DatabaseLaunchTests.Subject(regionalSettings: Self.kilograms, in: before.directory)
        after.launch.open()
        await after.launch.resume(isForeground: true)
        #expect(after.launch.settings.units == .lb)
        #expect(after.launch.settings.weekStart == .monday)
    }
}
