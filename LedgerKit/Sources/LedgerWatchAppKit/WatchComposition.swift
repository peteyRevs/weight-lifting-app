import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
#if canImport(WatchConnectivity)
    import LedgerSync
#endif
import Observation

/// The watch app's composition root (architecture §4, §13): its own database, the one place live values are bound
/// to the dependency keys. `App.init` calls `launch()`, which opens the database synchronously; the root view
/// then calls `resume(in:)` for the rest (`Launch.swift`) and renders `state`. `WatchAppDelegate` receives the
/// workout launches.
@MainActor
@Observable
public final class WatchComposition {
    public enum State: Equatable, Sendable {
        /// Nothing booted: the process is hosting tests, which must not write into the simulator's container.
        case idle
        /// The database is open and the keys are bound.
        case ready
        /// The database could not be opened (product decision #29).
        case databaseUnavailable
    }

    public internal(set) var state = State.idle
    /// The lifter's settings; `Settings.default` until they load, or when the stored row cannot be read, and
    /// then only in memory: it is never saved over that row (F05 input).
    public internal(set) var settings = Settings.default
    /// False until the catalog is seeded (product decision #28).
    public internal(set) var isCatalogSeeded = false

    @ObservationIgnored var stores: LedgerStores?
    @ObservationIgnored var hasResumed = false
    @ObservationIgnored var hasLoadedSettings = false
    @ObservationIgnored var isCompanionActive = false
    @ObservationIgnored let environment: Environment

    init(_ environment: Environment) {
        self.environment = environment
    }

    /// The app's composition, booted (`boot()`): call it once, from `App.init`. A process hosting tests boots
    /// nothing (`isTesting`). The launch argument `-LEDGER_UITEST` opens a fresh database file in a new temporary
    /// directory.
    public static func launch() -> WatchComposition {
        let composition = WatchComposition(.live(arguments: ProcessInfo.processInfo.arguments))
        if !isTesting {
            composition.boot()
        }
        return composition
    }

    /// Binds the six stores and this device's id; binds nothing until the database is open. The logger and the
    /// device keys keep their live values (the device ones are stubs until F16–F23).
    public func bind(_ values: inout DependencyValues) {
        guard let stores else {
            return
        }
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

        static func live(arguments: [String]) -> Environment {
            let launchLogger = LedgerLogger(category: "launch")
            #if canImport(WatchConnectivity)
                let activator = CompanionSessionActivator()
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
                preparesDependencies: true
            )
        }
    }
}
