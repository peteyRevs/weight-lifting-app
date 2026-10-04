import Foundation
import LedgerDomain
import Observation
import os

/// A step of either app's launch (F07 brief, "Launch sequence"; architecture §4), in the order the steps run.
/// `DatabaseLaunch` runs and records the database steps; the umbrellas run and record the platform ones (the
/// iPhone's mirroring handler, WatchConnectivity).
public enum LaunchStep: String, Sendable, CaseIterable {
    /// In `App.init`, synchronously: no `await` can run before these.
    case assignMirroringHandler, openDatabase
    /// After the first frame.
    case seedCatalog, loadSettings, activateCompanionSession
}

/// What a launch records: each step as it begins, and each step that fails (after logging it at fault level). A
/// step a cancellation interrupts did not fail and records nothing more.
public enum LaunchEvent: Hashable, Sendable {
    case began(LaunchStep)
    case failed(LaunchStep)
}

/// The database half of both apps' launch, shared by the two composition roots (architecture §4): opens the file
/// (product decision #29), then seeds the catalog (#28) and loads the settings, and retries what failed.
@MainActor
@Observable
public final class DatabaseLaunch {
    public enum State: Equatable, Sendable {
        /// Not opened: the process is hosting tests, which must not write into the simulator's container.
        case idle
        /// The database is open.
        case ready
        /// The database could not be opened (product decision #29).
        case databaseUnavailable
    }

    public private(set) var state = State.idle
    /// The lifter's settings; `Settings.default` until they load, or when the stored row cannot be read, and then
    /// only in memory: it is never saved over that row, which a later version may still read (F05 input).
    public private(set) var settings = Settings.default
    /// False until the catalog is seeded (product decision #28).
    public private(set) var isCatalogSeeded = false
    @ObservationIgnored public private(set) var stores: LedgerStores?

    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private let kind: LocalDevice.Kind
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let newID: @Sendable () -> UUID
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let record: (LaunchEvent) -> Void
    @ObservationIgnored private let onOpen: (LedgerStores) -> Void
    @ObservationIgnored private var hasResumed = false
    /// The task of each step that is running; the launch owns it, so cancelling a caller never cancels it.
    @ObservationIgnored private var running: [LaunchStep: Task<Void, Never>] = [:]
    /// The steps that have run to an outcome: done, or failed (logged and recorded).
    @ObservationIgnored private var ended: Set<LaunchStep> = []

    /// - Parameters:
    ///   - record: receives each `LaunchEvent` as it happens.
    ///   - onOpen: called once the database is open, before `state` becomes `.ready`: the composition root binds
    ///     the stores to the dependency keys there.
    public init(
        at databaseURL: URL,
        kind: LocalDevice.Kind,
        now: @escaping @Sendable () -> Date,
        newID: @escaping @Sendable () -> UUID,
        logger: Logger,
        record: @escaping (LaunchEvent) -> Void,
        onOpen: @escaping (LedgerStores) -> Void
    ) {
        self.databaseURL = databaseURL
        self.kind = kind
        self.now = now
        self.newID = newID
        self.logger = logger
        self.record = record
        self.onOpen = onOpen
    }

    /// Opens the database synchronously (`LedgerStores.open`), or shows decision #29's screen. A file that cannot
    /// be used is never deleted, moved, replaced or written: it stays for the next attempt.
    public func open() {
        record(.began(.openDatabase))
        do {
            let opened = try LedgerStores.open(at: databaseURL, kind: kind, now: now, newID: newID)
            stores = opened
            onOpen(opened)
            state = .ready
        } catch {
            state = .databaseUnavailable
            fail(.openDatabase, error)
        }
    }

    /// The asynchronous part: the seed, then the settings. A step that has not started starts, whatever the phase
    /// (a workout can launch the watch app in the background). A failed open (#29) and a failed seed (#28) retry
    /// only in the foreground. A settings row that cannot be read is not retried: it reads the same until the lifter
    /// saves.
    ///
    /// The launch owns each step's task, and a call that finds a step running waits for that same task, so a call
    /// returns once every step it reached has an outcome. Cancelling a call (`.task(id: scenePhase)` cancels on a
    /// phase change) cancels no step: each step always reaches an outcome, and is never begun twice.
    public func resume(isForeground: Bool) async {
        guard state != .idle else {
            return
        }
        if hasResumed, isForeground, state == .databaseUnavailable {
            open()
        }
        hasResumed = true
        guard let stores else {
            return
        }
        let seedCanRetry = isForeground && !isCatalogSeeded
        if let seed = task(for: .seedCatalog, retrying: seedCanRetry, { await self.seedCatalog(stores) }) {
            await seed.value
        }
        if let load = task(for: .loadSettings, retrying: false, { await self.loadSettings(stores) }) {
            await load.value
        }
    }

    /// The step's running task; else a new one when the step has not run, or has run and `retrying`; else nil. The
    /// main actor makes the check and the start one step, so two calls never start a step twice.
    private func task(
        for step: LaunchStep,
        retrying: Bool,
        _ body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        if let task = running[step] {
            return task
        }
        guard retrying || !ended.contains(step) else {
            return nil
        }
        let task = Task {
            await body()
            running[step] = nil
            ended.insert(step)
        }
        running[step] = task
        return task
    }

    private func seedCatalog(_ stores: LedgerStores) async {
        record(.began(.seedCatalog))
        do {
            try await stores.seedCatalog()
            isCatalogSeeded = true
        } catch {
            fail(.seedCatalog, error)
        }
    }

    private func loadSettings(_ stores: LedgerStores) async {
        record(.began(.loadSettings))
        do {
            settings = try await stores.settings.load()
        } catch {
            fail(.loadSettings, error)
        }
    }

    private func fail(_ step: LaunchStep, _ error: any Error) {
        logger.fault("Launch step \(step.rawValue, privacy: .public) failed: \(String(describing: error))")
        record(.failed(step))
    }
}
