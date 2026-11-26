import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerHealth
import LedgerPersistence
import LedgerSync
import SwiftUI

/// The watch app's composition root (architecture §4, §13): its own database, the one place live values are bound
/// to the dependency keys. `App.init` calls `launch()`, which opens the database synchronously; the root view
/// calls `resume(in:)` for the rest and renders `state`. The database half of the launch is `DatabaseLaunch`, which
/// the iPhone shares; the watch is the primary workout session (ADR-005), so it assigns no mirroring handler.
/// `WatchAppDelegate` receives the workout launches. The live workout's host is built when the database opens
/// and connected to the phone by `connectLiveSync()` (F17 S7b).
@MainActor
public final class WatchComposition {
    public typealias State = DatabaseLaunch.State

    let environment: Environment
    /// Built on first use, so that opening the database can hand the stores back to this composition.
    private(set) lazy var database = DatabaseLaunch(
        at: environment.databaseURL,
        kind: .watch,
        now: environment.now,
        newID: environment.newID,
        logger: environment.logger.log,
        record: environment.record,
        onOpen: { [weak self] stores in self?.opened(stores) }
    )
    /// The live workout's host over the open database: what `workoutSession` is bound to.
    private(set) var session: LocalWorkoutSessionActor?
    /// Mirroring and WatchConnectivity as one transport, when the environment has both channels.
    private(set) var transport: CompositeTransport?
    /// Runs the transport, the health events' broadcast and the phone-start rule, for the app's life.
    private var liveSync: Task<Void, Never>?
    private var isCompanionActive = false

    init(_ environment: Environment) {
        self.environment = environment
    }

    /// The database is open: builds the host and the transport over its stores and, in the app, binds the keys.
    private func opened(_ stores: LedgerStores) {
        session = LocalWorkoutSessionActor(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            device: stores.deviceID,
            now: environment.now
        )
        if let healthStore = environment.healthStore, let watchConnectivity = environment.watchConnectivity {
            transport = CompositeTransport(
                mirroring: MirroringTransport(channel: healthStore.remoteChannel, clock: environment.syncClock),
                watchConnectivity: watchConnectivity,
                clock: environment.syncClock
            )
        }
        if environment.preparesDependencies {
            prepareDependencies { bind(&$0) }
        }
    }

    public var state: State {
        database.state
    }

    /// The lifter's settings, or `Settings.default` in memory only (`DatabaseLaunch.settings`).
    public var settings: LedgerDomain.Settings {
        database.settings
    }

    /// False until the catalog is seeded (product decision #28).
    public var isCatalogSeeded: Bool {
        database.isCatalogSeeded
    }

    var stores: LedgerStores? {
        database.stores
    }

    /// Launch-to-first-frame (product decision #30): from the process's start to the root's first appearance. Nil
    /// until the root appears, or when the kernel gave no start time.
    private(set) var launchToFirstFrame: Duration?

    /// The app's composition, booted (`boot()`): call it once, from `App.init`. A process hosting unit tests boots
    /// nothing (`isTesting`), unless it is the app a UI test launched with `-LEDGER_UITEST`, which boots on a
    /// fresh database file in a new temporary directory.
    public static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> WatchComposition {
        let composition = WatchComposition(.live(arguments: arguments))
        if boots(arguments: arguments, isTesting: isTesting) {
            composition.boot()
        }
        return composition
    }

    static func boots(arguments: [String], isTesting: Bool) -> Bool {
        !isTesting || arguments.contains("-LEDGER_UITEST")
    }

    /// The launch's synchronous part, from `App.init`: the database is open before the first frame.
    func boot() {
        database.open()
    }

    /// The launch's asynchronous part, from the root view's `.task(id: scenePhase)`: the database half
    /// (`DatabaseLaunch.resume(isForeground:)`), then WatchConnectivity, activated once.
    public func resume(in phase: ScenePhase) async {
        guard state != .idle else {
            return
        }
        await database.resume(isForeground: phase == .active)
        await connectLiveSync()
        if !isCompanionActive {
            environment.record(.began(.activateCompanionSession))
            isCompanionActive = true
            environment.activateCompanionSession()
        }
    }

    /// Connects the host to the phone, once (F17 S7b), before WatchConnectivity is activated: runs the transport, a
    /// `HealthEventBroadcast` over the health store's events (their one reader; F18's screen subscribes too), and
    /// the host's answer to each start the phone asks for (`followPhoneStartRequests`), which adopts the phone's
    /// workout or, after 5 s, calls `startOwnWorkout`. Without a transport, nothing.
    func connectLiveSync() async {
        guard liveSync == nil, let session, let transport, let healthStore = environment.healthStore else {
            return
        }
        let broadcast = HealthEventBroadcast(healthStore.events)
        let phoneStarts = await broadcast.subscribe()
        let clock = environment.syncClock
        let startOwn = environment.startOwnWorkout
        liveSync = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await transport.run() }
                group.addTask { await broadcast.run() }
                group.addTask { await session.followPhoneStartRequests(phoneStarts, clock: clock, startOwn: startOwn) }
            }
        }
        await session.connect(transport, clock: clock)
    }

    /// The root view calls this when it first appears: measures launch-to-first-frame once and logs it.
    func rootAppeared() {
        guard launchToFirstFrame == nil, let start = environment.processStart else {
            return
        }
        let elapsed = Duration.seconds(environment.now().timeIntervalSince(start))
        launchToFirstFrame = elapsed
        let milliseconds = Int((elapsed / .milliseconds(1)).rounded())
        environment.logger.log.notice("First frame \(milliseconds, privacy: .public) ms after the process started")
    }

    /// Binds the six stores, this device's id, the health store (F16 S3a), the live workout's host and the live
    /// connection (F17 S7b); binds nothing until the database is open. The logger and the other device keys keep
    /// their live values (stubs until F18–F23).
    public func bind(_ values: inout DependencyValues) {
        if let stores {
            Self.bind(stores, into: &values)
            if let healthStore = environment.healthStore {
                values.healthStore = healthStore
            }
            if let session {
                values.workoutSession = session
            }
            if let transport {
                values.liveConnection = transport
            }
        }
    }

    static func bind(_ stores: LedgerStores, into values: inout DependencyValues) {
        values.exerciseRepository = stores.exercises
        values.programRepository = stores.programs
        values.workoutRepository = stores.workouts
        values.workoutEventStore = stores.events
        values.settingsRepository = stores.settings
        values.statsQueries = stores.stats
        values.deviceID = stores.deviceID
    }
}

extension WatchComposition {
    /// What the launch touches outside itself, so a test runs it on a temporary directory with stand-ins.
    struct Environment {
        var databaseURL: URL
        var now: @Sendable () -> Date
        var newID: @Sendable () -> UUID
        var logger: LedgerLogger
        /// Receives each `LaunchEvent` as it happens.
        var record: (LaunchEvent) -> Void
        var activateCompanionSession: () -> Void
        /// Whether opening the database binds the keys process-wide (`prepareDependencies`): the app only.
        var preparesDependencies: Bool
        /// When this process started (`ProcessStart`), where launch-to-first-frame begins.
        var processStart: Date?
        /// The watch's HealthKit session (`LiveHealthStore`); nil binds none, as in a test.
        var healthStore: (any HealthStore)?
        /// The live workout's WatchConnectivity channel (the activator's transport); nil connects no live sync.
        var watchConnectivity: (any LiveWorkoutTransport)?
        /// The live transports', the host's and the phone-start rule's timers.
        var syncClock: any Clock<Duration> = ContinuousClock()
        /// What starts the watch's own workout when the phone asked for one and its workout did not arrive within
        /// 5 s (F17 criterion 8). The seam for F18/F19: the cached day (F19) started from the workout screen (F18).
        /// Until then it only logs.
        var startOwnWorkout: @Sendable () async -> Void = {}

        static func live(arguments: [String]) -> Environment {
            let launchLogger = LedgerLogger(category: "launch")
            #if canImport(WatchConnectivity)
                let activator = CompanionSessionActivator()
                let liveChannel: (any LiveWorkoutTransport)? = activator.transport
            #else
                let liveChannel: (any LiveWorkoutTransport)? = nil
            #endif
            #if os(watchOS)
                let liveHealthStore: (any HealthStore)? = LiveHealthStore()
            #else
                let liveHealthStore: (any HealthStore)? = nil
            #endif
            return Environment(
                databaseURL: arguments.contains("-LEDGER_UITEST")
                    ? URL.temporaryDirectory.appending(path: "LedgerUITest-\(UUID().uuidString)/ledger.sqlite")
                    : LedgerStores.defaultURL,
                now: { Date() },
                newID: { UUID() },
                logger: launchLogger,
                record: { event in launchLogger.log.debug("Launch: \(String(describing: event), privacy: .public)") },
                activateCompanionSession: {
                    #if canImport(WatchConnectivity)
                        activator.activate()
                    #endif
                },
                preparesDependencies: true,
                processStart: ProcessStart.date(),
                healthStore: liveHealthStore,
                watchConnectivity: liveChannel,
                startOwnWorkout: {
                    launchLogger.log.notice("The watch would start its own workout here (F18/F19); nothing started")
                }
            )
        }
    }
}
