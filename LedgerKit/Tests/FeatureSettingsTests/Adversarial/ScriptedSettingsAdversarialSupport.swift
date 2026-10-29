@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S1a, G2: a `SettingsRepository` whose every save waits for the test to say how it ends, and whose
/// observation can hold its echoes back, as GRDB's `.task`-scheduled observation delivers a commit's value some
/// time after `write` has returned to the saver. Saves are recorded with the most that ever ran at once.
///
/// A held echo goes to the observations there were when its value was committed (fix round 2): an observation
/// started later begins with the row as it is, and never hears of a commit made before it, as a GRDB observation
/// starts with a fetch. `deliverNewestEcho()` sends only the newest held echo, as GRDB's `bufferingNewest(1)`
/// coalesces; `writeElsewhere(_:)` is a write made by another writer (G3's probes, F14-S1a-R1-1).
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
    private let holdsFirstValues: Bool
    /// Each held first value with the observation it goes to (fix round 3).
    private var waitingFirstValues: [(value: Settings, to: Int)] = []
    /// Each held echo with the observations it goes to.
    private var waitingEchoes: [(value: Settings, to: Set<Int>)] = []
    private var observers: [Int: AsyncStream<Settings>.Continuation] = [:]
    private var lastSent: [Int: Settings] = [:]
    private var endedFlags: [Int: EndedFlag] = [:]
    private var nextObserver = 0

    /// - Parameter holdsFirstValues: each observation's first value, the row as it is when the observation starts,
    ///   waits for `deliverNextFirstValue()`, as GRDB fetches it at once and delivers it later (F14-S1a-R2-2).
    init(_ settings: Settings, holdsEchoes: Bool = false, holdsFirstValues: Bool = false) {
        current = settings
        self.holdsEchoes = holdsEchoes
        self.holdsFirstValues = holdsFirstValues
    }

    /// Sends the oldest held first value to its observation, if that observation is still open.
    func deliverNextFirstValue() {
        lock.withLock {
            guard !waitingFirstValues.isEmpty else {
                return
            }
            let first = waitingFirstValues.removeFirst()
            observers[first.to]?.yield(first.value)
        }
    }

    var firstValuesWaiting: Int {
        lock.withLock { waitingFirstValues.count }
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

    /// Sends the oldest held echo to the observations it goes to.
    func deliverNextEcho() {
        lock.withLock {
            guard !waitingEchoes.isEmpty else {
                return
            }
            let echo = waitingEchoes.removeFirst()
            broadcast(echo.value, to: echo.to)
        }
    }

    /// Sends the newest held echo and drops the others, as an observation that coalesces its values does.
    func deliverNewestEcho() {
        lock.withLock {
            guard let echo = waitingEchoes.last else {
                return
            }
            waitingEchoes = []
            broadcast(echo.value, to: echo.to)
        }
    }

    /// Another writer puts `settings` in the row; its value goes to every observation at once.
    func writeElsewhere(_ settings: Settings) {
        lock.withLock {
            current = settings
            broadcast(settings, to: Set(observers.keys))
        }
    }

    /// The observations open now: those whose stream has not ended.
    var observationCount: Int {
        lock.withLock {
            dropEnded()
            return observers.count
        }
    }

    /// Under the lock: forgets the observations whose stream has ended.
    private func dropEnded() {
        for (id, flag) in endedFlags where flag.isSet {
            observers[id] = nil
            lastSent[id] = nil
            endedFlags[id] = nil
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
                    waitingEchoes.append((settings, Set(observers.keys)))
                } else {
                    broadcast(settings, to: Set(observers.keys))
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
        let ended = EndedFlag()
        let id = lock.withLock {
            let id = nextObserver
            nextObserver += 1
            observers[id] = continuation
            lastSent[id] = current
            if holdsFirstValues {
                waitingFirstValues.append((current, id))
            } else {
                continuation.yield(current)
            }
            return id
        }
        // Takes no lock (fix round 3): the runtime ends a stream holding its consumer task's lock, and `broadcast`
        // yields under `lock`, which takes that task's lock to resume it. The next delivery drops the observer.
        continuation.onTermination = { _ in ended.set() }
        lock.withLock { endedFlags[id] = ended }
        return stream
    }

    /// Under the lock. An observation that has ended is left out.
    private func broadcast(_ value: Settings, to ids: Set<Int>) {
        dropEnded()
        for (id, observer) in observers where ids.contains(id) && lastSent[id] != value {
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

    init(_ settings: Settings = Fixtures.settingsLb, holdsEchoes: Bool = false, holdsFirstValues: Bool = false) {
        let scripted = ScriptedSettings(settings, holdsEchoes: holdsEchoes, holdsFirstValues: holdsFirstValues)
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

    /// Turns the main actor 1,000 times: room for work that must not come, or that has no condition to wait on.
    func yieldALot() async {
        for _ in 0 ..< 1000 {
            await Task.yield()
        }
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
