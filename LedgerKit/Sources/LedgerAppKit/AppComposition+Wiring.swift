import Dependencies
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import LedgerSync

extension AppComposition {
    /// The database is open and `host` built: makes the health store with the host's answers (`HealthHooks`), and the
    /// transport over the health store's mirrored channel and the environment's WatchConnectivity channel (F17 S7b).
    func makeLiveSync(over host: LocalWorkoutSessionActor) {
        let hooks = HealthHooks(
            watchTookPart: { workout in await host.hasWatchParticipant(workout) },
            onMirrorStart: { [weak self] _ in await self?.connectLiveSync() }
        )
        healthStore = environment.makeHealthStore(hooks)
        if let healthStore, let watchConnectivity = environment.watchConnectivity {
            transport = CompositeTransport(
                mirroring: MirroringTransport(channel: healthStore.remoteChannel, clock: environment.syncClock),
                watchConnectivity: watchConnectivity,
                clock: environment.syncClock
            )
        }
    }

    /// Connects the host to the transport and runs the transport, once (F17 S7b): from `resume(in:)`, after the
    /// recovery and before WatchConnectivity is activated, and from each mirrored start (`HealthHooks`), since a
    /// background launch that mirroring made may connect no scene. The host's link-up handshakes recover first, so a
    /// launch in the background resumes its workout too. Without a transport, or before the database opens, nothing.
    func connectLiveSync() async {
        guard liveSync == nil, let session, let transport else {
            return
        }
        liveSync = Task { await transport.run() }
        await session.connect(transport, clock: environment.syncClock)
    }

    /// Binds the six stores, this device's id, the live workout's host, the haptics its cover plays and the
    /// announcements it makes (F10 S6, S7), the health store (F16 S3a) and the live connection (F17 S7b); binds
    /// nothing until the database is open. The app binds once, process-wide, through `prepareDependencies`; the
    /// logger and the other device keys keep their live values (stubs until F18–F23).
    public func bind(_ values: inout DependencyValues) {
        if let stores {
            Self.bind(stores, into: &values)
            if let healthStore {
                values.healthStore = healthStore
            }
            if let transport {
                values.liveConnection = transport
            }
        }
        if let session {
            values.workoutSession = session
            #if DEBUG
                if let failures = environment.failedFinishes {
                    // A UI test's failing save (`UITestSaveFailures`).
                    values.workoutSession = UITestFailingFinishSession(base: session, failures: failures)
                }
            #endif
            values.haptics = LiveHaptics()
            values.announcements = LiveAnnouncements()
        }
    }

    static func bind(_ stores: LedgerStores, into values: inout DependencyValues) {
        values.exerciseRepository = stores.exercises
        values.programRepository = stores.programs
        values.workoutRepository = stores.workouts
        values.workoutEventStore = stores.events
        values.settingsRepository = stores.settings
        values.statsQueries = stores.stats
        values.dataReset = stores.reset
        values.deviceID = stores.deviceID
    }
}
