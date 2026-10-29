import Dependencies
@testable import FeatureSettings
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Observation
import Testing

/// Tags live in the test target (F00 implementation notes #6), as `LedgerDesignTests`' do.
extension Tag {
    /// Every FeatureSettings suite (layer tag, testing-strategy §6).
    @Tag static var feature: Self
    /// Suites that compare against committed `__Snapshots__` references.
    @Tag static var snapshot: Self
}

/// Waits until `condition` holds, by watching what it reads (Observation), never by time. A condition that never
/// holds ends at the suite's time limit.
@MainActor
func eventually(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations({ condition() }) where holds {
        return
    }
}

/// The About line's values the tests pass: a stand-in's, never the app's (N6).
nonisolated enum SettingsFixtures {
    static let about = AppAbout(name: "App", version: "1.2.3", build: "45")
}

/// The settings of `base`, with what the store's tests need to see and to stop: every `save` recorded, the next
/// `failures` saves refused, saves held until released, and a row this app cannot read until a save replaces it
/// (F05's unreadable row: `observe()` ends with no value and `load()` throws).
final nonisolated class WatchedSettings: SettingsRepository, @unchecked Sendable {
    struct Refused: Error {}

    private let base: InMemorySettingsRepository
    private let lock = NSLock()
    private var saved: [Settings] = []
    private var failures: Int
    private var holdsSaves: Bool
    private var isUnreadable: Bool
    private var running = 0
    private var mostRunning = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ base: InMemorySettingsRepository, failures: Int = 0, holdsSaves: Bool = false, unreadable: Bool = false) {
        self.base = base
        self.failures = failures
        self.holdsSaves = holdsSaves
        isUnreadable = unreadable
    }

    /// Every settings `save` was called with, in order, the refused ones too.
    var saves: [Settings] {
        lock.withLock { saved }
    }

    /// The most saves that ever ran at once.
    var mostAtOnce: Int {
        lock.withLock { mostRunning }
    }

    var isHoldingSave: Bool {
        lock.withLock { !waiters.isEmpty }
    }

    /// Lets the held saves go on; with `keepHolding`, the saves after them are held too.
    func releaseSaves(keepHolding: Bool = false) {
        let waiting = lock.withLock {
            holdsSaves = keepHolding
            defer { waiters = [] }
            return waiters
        }
        for waiter in waiting {
            waiter.resume()
        }
    }

    func load() async throws -> Settings {
        if lock.withLock({ isUnreadable }) {
            throw Refused()
        }
        return try await base.load()
    }

    func save(_ settings: Settings) async throws {
        let (holds, refuses) = lock.withLock {
            saved.append(settings)
            running += 1
            mostRunning = max(mostRunning, running)
            defer { failures -= 1 }
            return (holdsSaves, failures > 0)
        }
        defer { lock.withLock { running -= 1 } }
        if holds {
            await withCheckedContinuation { continuation in
                let resume = lock.withLock {
                    guard holdsSaves else {
                        return true
                    }
                    waiters.append(continuation)
                    return false
                }
                if resume {
                    continuation.resume()
                }
            }
        }
        if refuses {
            throw Refused()
        }
        try await base.save(settings)
        lock.withLock { isUnreadable = false }
    }

    func seedIfAbsent(_ settings: Settings) async throws {
        try await base.seedIfAbsent(settings)
    }

    func observe() -> AsyncStream<Settings> {
        lock.withLock { isUnreadable } ? AsyncStream { $0.finish() } : base.observe()
    }
}

/// A `SettingsStore` and what it saves to, under test: the settings in pounds behind `WatchedSettings`, en_US and
/// Fixtures' calendar (weeks listed from Sunday). The store is made inside `withTestDependencies`, so its
/// dependencies are the scene's for its whole life.
@MainActor
struct SettingsScene {
    let memory: InMemoryStores
    let watched: WatchedSettings
    let store: SettingsStore

    init(
        settings: Settings = Fixtures.settingsLb,
        failures: Int = 0,
        holdsSaves: Bool = false,
        unreadable: Bool = false
    ) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(settings: settings))
        let probe = WatchedSettings(
            stores.settings,
            failures: failures,
            holdsSaves: holdsSaves,
            unreadable: unreadable
        )
        memory = stores
        watched = probe
        store = withTestDependencies {
            $0.settingsRepository = probe
        } operation: {
            SettingsStore(about: SettingsFixtures.about)
        }
    }

    /// The store's run, as `SettingsRoot`'s task runs it, once it shows a model. The task is the root's: a test
    /// cancels it where the view would go away.
    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.model != nil }
        return task
    }

    /// Returns once a save is held by `WatchedSettings`, which Observation cannot watch.
    func untilASaveIsHeld() async {
        while !watched.isHoldingSave {
            await Task.yield()
        }
    }

    /// The model on screen.
    var model: SettingsModel {
        get throws {
            try #require(store.model)
        }
    }

    /// The settings stored now.
    func stored() async throws -> Settings {
        try await memory.settings.load()
    }
}
