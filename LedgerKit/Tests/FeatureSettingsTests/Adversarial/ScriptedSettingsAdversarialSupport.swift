@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1a, G2: a `SettingsRepository` whose every save waits for the test to say how it ends, and whose
/// observation can hold its echoes back, as GRDB's `.task`-scheduled observation delivers a commit's value some
/// time after `write` has returned to the saver. Saves are recorded with the most that ever ran at once.
final nonisolated class ScriptedSettings: SettingsRepository, @unchecked Sendable {
    struct Refused: Error {}

    private struct Held {
        let value: Settings
        let resume: CheckedContinuation<Bool, Never>
    }

    private let lock = NSLock()
    private var current: Settings
    private var held: [Held] = []
    private var saved: [Settings] = []
    private var running = 0
    private var mostRunning = 0
    private let holdsEchoes: Bool
    private var waitingEchoes: [Settings] = []
    private var observers: [Int: AsyncStream<Settings>.Continuation] = [:]
    private var lastSent: [Int: Settings] = [:]
    private var nextObserver = 0

    init(_ settings: Settings, holdsEchoes: Bool = false) {
        current = settings
        self.holdsEchoes = holdsEchoes
    }

    /// The row now.
    var row: Settings {
        lock.withLock { current }
    }

    /// Every value `save` was called with, in order.
    var saves: [Settings] {
        lock.withLock { saved }
    }

    var mostAtOnce: Int {
        lock.withLock { mostRunning }
    }

    /// The values of the saves waiting for the test, oldest first.
    var heldValues: [Settings] {
        lock.withLock { held.map(\.value) }
    }

    var echoesWaiting: Int {
        lock.withLock { waitingEchoes.count }
    }

    /// Ends the oldest held save: committed (the row changes and its echo is sent or held) or refused.
    func resolveNext(commit: Bool) {
        let next: Held? = lock.withLock { held.isEmpty ? nil : held.removeFirst() }
        next?.resume.resume(returning: commit)
    }

    /// Sends the oldest held echo to every observer.
    func deliverNextEcho() {
        lock.withLock {
            guard !waitingEchoes.isEmpty else {
                return
            }
            broadcast(waitingEchoes.removeFirst())
        }
    }

    func load() async throws -> Settings {
        row
    }

    func save(_ settings: Settings) async throws {
        lock.withLock {
            saved.append(settings)
            running += 1
            mostRunning = max(mostRunning, running)
        }
        let commits = await withCheckedContinuation { continuation in
            lock.withLock { held.append(Held(value: settings, resume: continuation)) }
        }
        lock.withLock {
            running -= 1
            if commits {
                current = settings
                if holdsEchoes {
                    waitingEchoes.append(settings)
                } else {
                    broadcast(settings)
                }
            }
        }
        if !commits {
            throw Refused()
        }
    }

    func seedIfAbsent(_: Settings) async throws {}

    /// The row now, then each echo, an echo equal to the last one sent left out (GRDB's `removeDuplicates`).
    func observe() -> AsyncStream<Settings> {
        let (stream, continuation) = AsyncStream<Settings>.makeStream()
        let id = lock.withLock {
            let id = nextObserver
            nextObserver += 1
            observers[id] = continuation
            lastSent[id] = current
            continuation.yield(current)
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock {
                self?.observers[id] = nil
                self?.lastSent[id] = nil
            }
        }
        return stream
    }

    /// Under the lock.
    private func broadcast(_ value: Settings) {
        for (id, observer) in observers where lastSent[id] != value {
            lastSent[id] = value
            observer.yield(value)
        }
    }
}

/// A `SettingsStore` over `ScriptedSettings`, with waits that poll what Observation cannot watch. A wait that
/// never holds records an issue after `limit` turns instead of hanging (no clock is read).
@MainActor
struct ScriptedSettingsScene {
    let repository: ScriptedSettings
    let store: SettingsStore

    init(_ settings: Settings = Fixtures.settingsLb, holdsEchoes: Bool = false) {
        let scripted = ScriptedSettings(settings, holdsEchoes: holdsEchoes)
        repository = scripted
        store = withTestDependencies {
            $0.settingsRepository = scripted
        } operation: {
            SettingsStore(about: SettingsFixtures.about)
        }
    }

    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.model != nil }
        return task
    }

    /// Turns the main actor until `condition` holds; false, with an issue, after `limit` turns.
    @discardableResult
    func until(
        _ what: String,
        limit: Int = 200_000,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async -> Bool {
        for _ in 0 ..< limit {
            if condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("never held: \(what)", sourceLocation: sourceLocation)
        return false
    }

    /// Waits for `count` saves to be held.
    func untilHeld(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        await until("\(count) save(s) held", sourceLocation: sourceLocation) { repository.heldValues.count >= count }
    }

    /// The store has caught up: it has read the row, and it either waits on a held save or has nothing pending.
    func settle(sourceLocation: SourceLocation = #_sourceLocation) async {
        await until("the store settles", sourceLocation: sourceLocation) {
            store.stored == repository.row && (store.pending == nil || repository.heldValues.count == 1)
        }
    }
}
