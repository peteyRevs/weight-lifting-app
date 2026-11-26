import Dependencies
import FeatureWorkout
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import LedgerSync
import SwiftUI

/// The iPhone app's composition root (architecture §4, §13): the one place live values are bound to the
/// dependency keys. `App.init` calls `launch()`, which assigns the mirroring handler, then opens the database,
/// synchronously; the root view calls `resume(in:)` for the rest and renders `state`. The database half of the
/// launch is `DatabaseLaunch`, which the watch shares; what is the iPhone's own is here.
@MainActor
public final class AppComposition {
    public typealias State = DatabaseLaunch.State

    let environment: Environment
    /// Built on first use, so that opening the database can hand the stores back to this composition.
    private(set) lazy var database = DatabaseLaunch(
        at: environment.databaseURL,
        kind: .phone,
        regionalSettings: environment.regionalSettings,
        now: environment.now,
        newID: environment.newID,
        logger: environment.logger.log,
        record: environment.record,
        onOpen: { [weak self] stores in self?.opened(stores) }
    )
    /// The live workout's host over the open database (F10): what `workoutSession` is bound to.
    private(set) var session: LocalWorkoutSessionActor?
    /// The phone's health store, made when the database opens with the host's answers (`HealthHooks`).
    var healthStore: (any HealthStore)?
    /// Mirroring and WatchConnectivity as one transport (F17 S7b), when the environment has both channels.
    var transport: CompositeTransport?
    /// Runs `transport` for the app's life, once the host is connected to it (`connectLiveSync()`).
    var liveSync: Task<Void, Never>?
    private var isCompanionActive = false
    #if DEBUG
        /// Whether `saveUITestProgramIfAsked()` has run in this process: it runs once.
        private var isUITestProgramDone = false
    #endif

    init(_ environment: Environment) {
        self.environment = environment
    }

    /// The database is open, and `state` is not yet `.ready`: builds the live workout's host over its stores
    /// and, in the app, binds the keys process-wide.
    ///
    /// The host is given no `NotificationsClient` (F10 S6): the rest-over notification and its permission are
    /// F23's, which passes its client here. Until then a rest that starts schedules nothing, and nothing
    /// calls the `notifications` key's stub.
    private func opened(_ stores: LedgerStores) {
        let host = LocalWorkoutSessionActor(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            device: stores.deviceID,
            now: environment.now
        )
        session = host
        makeLiveSync(over: host)
        if environment.preparesDependencies {
            prepareDependencies {
                bind(&$0)
                if environment.clockOffset != nil {
                    // A UI test's date (`UITestClock`): the stores' clock is the launch's.
                    $0.date = DateGenerator(environment.now)
                }
            }
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
    /// of #28 and #29), then the live workout's recovery, then WatchConnectivity, activated once.
    ///
    /// The recovery (`LocalWorkoutSessionActor.resumeFromStore()`, F10) resumes a workout the app was killed in
    /// and stores one it was killed while saving. It runs once the database is open, and again on a return to
    /// the foreground while the host has work left: a recovery that failed, or a finish whose save failed.
    public func resume(in phase: ScenePhase) async {
        guard state != .idle else {
            return
        }
        await database.resume(isForeground: phase == .active)
        if let session {
            let hasWorkLeft = await session.needsRecovery
            await database.run(.resumeWorkout, retrying: phase == .active && hasWorkLeft) {
                try await session.resumeFromStore()
            }
        }
        await connectLiveSync()
        if !isCompanionActive {
            environment.record(.began(.activateCompanionSession))
            isCompanionActive = true
            environment.activateCompanionSession()
        }
    }

    /// What onboarding's "Retry" awaits before it saves again (F08, ruling O13): the database half of the launch
    /// once more, as in the foreground. While the catalog is unseeded it starts the seed step again (product
    /// decision #28), or waits for the one that is running; a step that has succeeded is not run again.
    ///
    /// It is not `resume(in:)`, and must stay this narrow. Every control of onboarding is disabled while it
    /// runs, so it has to return: here that is one local transaction that commits or throws. The workout's
    /// recovery and the device steps are the launch's to run and to retry, not a lifter's tap on "Retry".
    func retrySeed() async {
        await database.resume(isForeground: true)
    }

    /// A UI test's program (`UITestProgram`, F08 ruling R2): once the launch's pass has run, and before the
    /// root's gate first reads the active program, saves the spec's seed program as the active one when there
    /// is none, as the Debug menu's sample does, then its past workouts when asked (`UITestHistory`, F15 S1). Once
    /// in a process, and only when the launch asked for it (two calls that overlap may both save, and leave one
    /// program only because the seed program's id is fixed); a failure is logged, and the test then finds
    /// onboarding, or no history. A call whose task is cancelled (the scene's phase changed during the launch's
    /// first pass) does not count: the next pass makes it. A Release build does nothing here.
    func saveUITestProgramIfAsked() async {
        #if DEBUG
            guard environment.seedsUITestProgram, !isUITestProgramDone, !Task.isCancelled, let stores else {
                return
            }
            do {
                try await SampleProgram.activeOrSeed(in: stores.programs)
                if let weeks = environment.uiTestHistoryWeeks {
                    try await UITestHistory.saveIfEmpty(weeks: weeks, in: stores.workouts)
                }
                isUITestProgramDone = true
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isUITestProgramDone = true
                let reason = String(describing: error)
                environment.logger.log.error(
                    "The UI test's program or its history was not saved: \(reason, privacy: .public)"
                )
            }
        #endif
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
        /// When this process started (`ProcessStart`), where launch-to-first-frame begins.
        var processStart: Date?
        /// The seconds `now` and `processStart` are moved by, when a UI test asked for a date (`UITestClock`).
        var clockOffset: TimeInterval?
        /// How many calls of the session's `finish` fail, when a UI test asked for that (`UITestSaveFailures`).
        var failedFinishes: Int?
        /// Whether a UI test asked for the seed program (`UITestProgram`).
        var seedsUITestProgram = false
        /// The weeks of the seed program's workouts a UI test asked for (`UITestHistory`), saved after it.
        var uiTestHistoryWeeks: Int?
        /// What a new install's settings start from (decision #15): the region's in the app, a US iPhone's under a UI
        /// test (`UITestRegion`). Nil seeds nothing, so a test's composition keeps `Settings.default` unless it asks
        /// for a region.
        var regionalSettings: LedgerDomain.Settings?
        /// The appearance a UI test asked for (`UITestAppearance`); nil follows the device.
        var colorScheme: ColorScheme?
        /// Makes the phone's HealthKit store over the mirroring handler's sessions (F16 S3a), once, when the
        /// database opens, with the host's answers (F17 S7b); nil binds none.
        var makeHealthStore: (HealthHooks) -> (any HealthStore)? = { _ in nil }
        /// The live workout's WatchConnectivity channel (the activator's transport); nil connects no live sync.
        var watchConnectivity: (any LiveWorkoutTransport)?
        /// The live transports' and the host's timers.
        var syncClock: any Clock<Duration> = ContinuousClock()

        static func live(arguments: [String]) -> Environment {
            let launchLogger = LedgerLogger(category: "launch")
            let health = liveHealth()
            #if canImport(WatchConnectivity)
                let activator = CompanionSessionActivator()
                let liveChannel: (any LiveWorkoutTransport)? = activator.transport
            #else
                let liveChannel: (any LiveWorkoutTransport)? = nil
            #endif
            let offset = UITestClock.liveOffset(arguments: arguments)
            let isUITest = arguments.contains("-LEDGER_UITEST")
            return Environment(
                databaseURL: isUITest
                    ? URL.temporaryDirectory.appending(path: "LedgerUITest-\(UUID().uuidString)/ledger.sqlite")
                    : LedgerStores.defaultURL,
                now: { Date().addingTimeInterval(offset ?? 0) },
                newID: { UUID() },
                logger: launchLogger,
                record: { event in launchLogger.log.debug("Launch: \(String(describing: event), privacy: .public)") },
                assignMirroringHandler: health.assignHandler,
                activateCompanionSession: {
                    #if canImport(WatchConnectivity)
                        activator.activate()
                    #endif
                },
                preparesDependencies: true,
                processStart: ProcessStart.date()?.addingTimeInterval(offset ?? 0),
                clockOffset: offset,
                failedFinishes: UITestSaveFailures.liveCount(arguments: arguments),
                seedsUITestProgram: UITestProgram.liveSeeds(arguments: arguments),
                uiTestHistoryWeeks: UITestHistory.liveWeeks(arguments: arguments),
                regionalSettings: UITestRegion.liveSettings(isUITest: isUITest),
                colorScheme: UITestAppearance.liveColorScheme(arguments: arguments),
                makeHealthStore: health.makeStore,
                watchConnectivity: liveChannel
            )
        }
    }
}
