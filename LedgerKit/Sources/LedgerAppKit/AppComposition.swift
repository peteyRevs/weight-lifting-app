import Dependencies
import Foundation
#if os(iOS)
    import HealthKit
#endif
import LedgerDependencies
import LedgerDomain
#if os(iOS)
    import LedgerHealth
#endif
import LedgerPersistence
#if canImport(WatchConnectivity)
    import LedgerSync
#endif
import SwiftUI

/// The iPhone app's composition root (architecture §4, §13): the one place live values are bound to the
/// dependency keys. `App.init` calls `launch()`, which assigns the mirroring handler, then opens the database,
/// synchronously; the root view calls `resume(in:)` for the rest and renders `state`. The database half of the
/// launch is `DatabaseLaunch`, which the watch shares; what is the iPhone's own is here.
@MainActor
public final class AppComposition {
    public typealias State = DatabaseLaunch.State

    let environment: Environment
    let database: DatabaseLaunch
    private var isCompanionActive = false

    init(_ environment: Environment) {
        self.environment = environment
        let preparesDependencies = environment.preparesDependencies
        database = DatabaseLaunch(
            at: environment.databaseURL,
            kind: .phone,
            now: environment.now,
            newID: environment.newID,
            logger: environment.logger.log,
            record: environment.record,
            onOpen: { stores in
                if preparesDependencies {
                    prepareDependencies { Self.bind(stores, into: &$0) }
                }
            }
        )
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

    /// The app's composition, booted (`boot()`): call it once, from `App.init`. A process hosting unit tests boots
    /// nothing (`isTesting`), unless it is the app a UI test launched with `-LEDGER_UITEST`, which boots on a
    /// fresh database file in a new temporary directory.
    public static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppComposition {
        let composition = AppComposition(.live(arguments: arguments))
        if boots(arguments: arguments, isTesting: isTesting) {
            composition.boot()
        }
        return composition
    }

    static func boots(arguments: [String], isTesting: Bool) -> Bool {
        !isTesting || arguments.contains("-LEDGER_UITEST")
    }

    /// The launch's synchronous part, from `App.init`. It is not `async`, so the compiler guarantees that no
    /// `await` runs before the mirroring handler is assigned (ADR-005, criterion 6); the handler goes first so a
    /// launch the watch's mirroring started gets its session even if the database then fails to open.
    func boot() {
        environment.record(.began(.assignMirroringHandler))
        environment.assignMirroringHandler()
        database.open()
    }

    /// The launch's asynchronous part, from the root view's `.task(id: scenePhase)`: the database half
    /// (`DatabaseLaunch.resume(isForeground:)`: the seed, the settings, and on return to the foreground the retries
    /// of #28 and #29), then WatchConnectivity, activated once.
    public func resume(in phase: ScenePhase) async {
        guard state != .idle else {
            return
        }
        await database.resume(isForeground: phase == .active)
        if !isCompanionActive {
            environment.record(.began(.activateCompanionSession))
            isCompanionActive = true
            environment.activateCompanionSession()
        }
    }

    /// Binds the six stores and this device's id; binds nothing until the database is open. The app binds once,
    /// process-wide, through `prepareDependencies`; the logger and the device keys keep their live values (the
    /// device ones are stubs until F16–F23).
    public func bind(_ values: inout DependencyValues) {
        if let stores {
            Self.bind(stores, into: &values)
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

extension AppComposition {
    /// What the launch touches outside itself, so a test runs it on a temporary directory with stand-ins.
    struct Environment {
        var databaseURL: URL
        var now: @Sendable () -> Date
        var newID: @Sendable () -> UUID
        var logger: LedgerLogger
        /// Receives each `LaunchEvent` as it happens.
        var record: (LaunchEvent) -> Void
        var assignMirroringHandler: () -> Void
        var activateCompanionSession: () -> Void
        /// Whether opening the database binds the keys process-wide (`prepareDependencies`): the app only. A
        /// test binds with `withDependencies { composition.bind(&$0) }`.
        var preparesDependencies: Bool

        static func live(arguments: [String]) -> Environment {
            let launchLogger = LedgerLogger(category: "launch")
            #if os(iOS)
                let registrar = MirroringStartRegistrar<HKWorkoutSession>()
            #endif
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
                assignMirroringHandler: {
                    #if os(iOS)
                        registrar.register()
                    #endif
                },
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
