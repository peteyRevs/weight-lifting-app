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
    @ObservationIgnored private var hasFinishedFirstPass = false
    @ObservationIgnored private var hasLoadedSettings = false
    @ObservationIgnored private var running: Set<LaunchStep> = []

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

    /// The asynchronous part. Until a first pass has run to its end, each call runs it, whatever the phase (a
    /// workout can launch the watch app in the background): the seed, then the settings. After that a call
    /// retries only in the foreground: opening again if unavailable (#29), then seeding if unseeded (#28). A
    /// settings row that cannot be read is not retried: it reads the same until the lifter saves.
    ///
    /// A step a cancellation interrupts (`.task(id: scenePhase)` cancels on a phase change) was not attempted: it
    /// logs nothing, and the next call runs it again. A step an overlapping call is already running is not
    /// started twice.
    public func resume(isForeground: Bool) async {
        guard state != .idle else {
            return
        }
        if hasFinishedFirstPass {
            guard isForeground else {
                return
            }
            if state == .databaseUnavailable {
                open()
            }
        }
        var finished = true
        if let stores {
            if !isCatalogSeeded {
                let outcome = await run(.seedCatalog) {
                    try await stores.seedCatalog()
                    self.isCatalogSeeded = true
                }
                finished = finished && outcome != .cancelled
            }
            if !hasLoadedSettings {
                let outcome = await run(.loadSettings) {
                    self.settings = try await stores.settings.load()
                }
                hasLoadedSettings = hasLoadedSettings || outcome == .attempted
                finished = finished && outcome != .cancelled
            }
        }
        hasFinishedFirstPass = hasFinishedFirstPass || finished
    }

    private enum Outcome {
        /// The step ran to an end: done, or failed (logged and recorded).
        case attempted
        /// A cancellation interrupted it: not attempted.
        case cancelled
        /// An overlapping call is running it.
        case elsewhere
    }

    private func run(_ step: LaunchStep, _ body: () async throws -> Void) async -> Outcome {
        guard running.insert(step).inserted else {
            return .elsewhere
        }
        defer { running.remove(step) }
        record(.began(step))
        do {
            try await body()
        } catch is CancellationError { // GRDB's async reads and writes in a cancelled task
            return .cancelled
        } catch {
            fail(step, error)
        }
        return .attempted
    }

    private func fail(_ step: LaunchStep, _ error: any Error) {
        logger.fault("Launch step \(step.rawValue, privacy: .public) failed: \(String(describing: error))")
        record(.failed(step))
    }
}
