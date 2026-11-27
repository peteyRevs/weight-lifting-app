import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The overlays the session list and "End workout" open over a live workout (spec §4.2).
nonisolated enum WatchOverlay: Equatable, Sendable {
    case list, end
}

/// The store of the watch's workout (M1 store convention; F18 criteria 2, 4, 9, 10, 11). Every screen's model is one
/// of `WatchPresentation`'s pure functions of what it holds. Like the phone's `WorkoutStore` it keeps no workout of its
/// own: every workout it shows is one `WorkoutSessionClient.updates()` published, whichever device's change it carries,
/// so a workout that replaces another (the phone's start won) shows in its place, never through idle. `run()` is the
/// root's `.task`; the intents are synchronous, and the taps that change the workout wait in a queue the pump applies
/// in order, each planned on the newest workout, so a double tap of "Done set" logs one set. Making one does nothing.
@MainActor @Observable
final class WatchWorkoutStore {
    /// The session's last workout: live, or ended in the update that ended it. Taps are planned only once this run's
    /// stream has said what it holds (`hasHeardSession`).
    private(set) var workout: WorkoutState?
    private(set) var hasHeardSession = false
    private(set) var program: Program?
    private(set) var hasHeardProgram = false
    private(set) var settings: Settings?
    private(set) var exercises: [ExerciseID: Exercise] = [:]
    /// The newest workouts in the watch's history, for "Logged earlier today".
    private(set) var recent: [WorkoutState] = []
    /// The live connection as last heard (F17 criterion 12), and whether any state but `solo` was heard, as the phone's
    /// `hasHeardTheWatch`: from then on `solo` means the iPhone is away, not absent. Never set back.
    private(set) var connection: LiveConnectionState?
    private(set) var hasHeardPhone = false
    /// The open overlay, shown only over a live mode (`shownOverlay`).
    var overlay: WatchOverlay?
    /// "Done" on the summary (a local flag, F18 criterion 11).
    var isSummaryDismissed = false
    var crown = CrownWeightModel()
    /// What the watch's Health session last said (`WatchHealthSession.states()`); without one, no session. Set only
    /// by `followHealth()` (`WatchWorkoutStore+Health.swift`), hence not `private(set)`.
    var healthState = WatchHealth()
    /// The records the finished workout on screen set, judged against the bests before it (decision #27); none
    /// until the read answers. Set by `show(_:)` and `followRecords(_:)`.
    var records: [PersonalRecord] = []

    /// The taps waiting for the pump, oldest first; the one being applied stays at the front until it is done.
    /// Observable only so that a test can wait for the taps to be applied.
    var queue: [WatchCommand] = []
    @ObservationIgnored var isDraining = false
    @ObservationIgnored var wake: AsyncStream<Void>.Continuation?
    /// The session's answer to the last change until the stream has shown it: what the next tap is planned on.
    @ObservationIgnored var ahead: WorkoutState?
    /// The session updates heard, for the tests that count emissions.
    @ObservationIgnored private(set) var updatesHeard = 0
    /// Moved by the rest's task at the rest's end and at the end of "GO" (`WatchWorkoutStore+Rest.swift`). Not
    /// `private(set)` because that task is the store's extension in its own file.
    var restEdges = 0
    /// The shown rest the rest's task (`restTask`) waits on.
    @ObservationIgnored var followedRest: RestTimer?
    @ObservationIgnored var restTask: Task<Void, Never>?
    /// Plays the updates' haptics and the rest's buzz, a turn at a time.
    @ObservationIgnored let haptic = WatchHapticPlayer()
    /// Each finished workout shown, for `followRecords()` to judge.
    @ObservationIgnored var finishedShown: AsyncStream<WorkoutState>.Continuation?

    @ObservationIgnored let appName: String
    @ObservationIgnored let healthSession: WatchHealthSession?
    @ObservationIgnored @Dependency(\.workoutSession) var session
    @ObservationIgnored @Dependency(\.liveConnection) private var liveConnection
    @ObservationIgnored @Dependency(\.programRepository) var programs
    @ObservationIgnored @Dependency(\.exerciseRepository) var exerciseRepository
    @ObservationIgnored @Dependency(\.workoutRepository) private var workoutRepository
    @ObservationIgnored @Dependency(\.settingsRepository) var settingsRepository
    @ObservationIgnored @Dependency(\.statsQueries) var stats
    @ObservationIgnored @Dependency(\.deviceID) var device
    @ObservationIgnored @Dependency(\.date) var date
    @ObservationIgnored @Dependency(\.continuousClock) var clock
    @ObservationIgnored @Dependency(\.haptics) private var haptics
    @ObservationIgnored @Dependency(\.uuid) var uuid
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger
    var logger: LedgerLogger {
        injectedLogger.category("watch.workout")
    }

    /// - Parameters:
    ///   - appName: the app's display name (`CFBundleDisplayName`), for "Open %@ on iPhone".
    ///   - health: the watch's Health session, which the composition runs; nil shows none.
    init(appName: String, health: WatchHealthSession? = nil) {
        self.appName = appName
        healthSession = health
    }

    /// How many of the newest workouts "Logged earlier today" looks through: more than a day ever holds.
    static let recentLimit = 8

    // MARK: What the screens draw

    var mode: WatchMode {
        WatchMode(workout, at: now, summaryDismissed: isSummaryDismissed)
    }

    var shownOverlay: WatchOverlay? {
        mode.isLive ? overlay : nil
    }

    var liveInput: WatchLiveInput {
        WatchLiveInput(
            heartRate: heartRate, health: health, connection: connection, hasHeardPhone: hasHeardPhone, locale: locale
        )
    }

    /// The screen before a workout; nil until the program and the settings have been heard.
    var idle: WatchIdleModel? {
        guard hasHeardProgram, let settings else {
            return nil
        }
        let isTodayLogged = program.map { program in
            WatchPresentation.isLogged(today: program, in: recent, settings: settings, now: now, calendar: calendar)
        } ?? false
        return WatchPresentation.idle(WatchIdleInput(
            program: program, exercises: exercises, workout: workout, isTodayLogged: isTodayLogged,
            settings: settings, now: now, calendar: calendar, locale: locale, appName: appName
        ))
    }

    var ready: WatchReadyModel? {
        live.flatMap { WatchPresentation.ready($0, at: now, liveInput) }
    }

    /// The crown's number as the set screen prints it, "190", which moves with the crown before anything is sent.
    var crownWeight: String? {
        crown.reading.flatMap { reading in crown.weight?.formatted(in: reading.units) }
    }

    /// The crown's weight on the set screen, as `CrownWeight` draws it and VoiceOver reads it.
    var crownDial: CrownDial? {
        WatchPresentation.crownDial(crown, locale: locale)
    }

    var rest: WatchRestModel? {
        live.flatMap { WatchPresentation.rest($0, mode: mode, at: now, liveInput) }
    }

    var list: WatchListModel? {
        live.map { WatchPresentation.list($0, locale: locale) }
    }

    var end: WatchEndModel? {
        live.map { WatchPresentation.end($0, locale: locale) }
    }

    var summary: WatchSummaryModel? {
        let shown = mode == .summary ? workout : nil
        return shown.map { WatchPresentation.summary($0, records: records, health: healthRecord, locale: locale) }
    }

    var live: WorkoutState? {
        workout?.phase == .live ? workout : nil
    }
}

// MARK: - Work the root's task runs

extension WatchWorkoutStore {
    /// Follows the session, the live connection, the program, the settings, the exercises, the newest history and the
    /// Health session, judges each finished workout's records, applies the taps, and plays the haptics, for as long
    /// as the root's task runs.
    func run() async {
        defer { stopFollowingRest() }
        let (finished, sink) = AsyncStream.makeStream(of: WorkoutState.self, bufferingPolicy: .bufferingNewest(1))
        finishedShown = sink
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followSession() }
            group.addTask { await self.followConnection() }
            group.addTask { await self.followHealth() }
            group.addTask { await self.followRecords(finished) }
            group.addTask {
                await self.follow(self.programs.observeActive()) { store, program in
                    store.program = program
                    store.hasHeardProgram = true
                }
            }
            group.addTask { await self.follow(self.settingsRepository.observe()) { $0.settings = $1 } }
            group.addTask {
                await self.follow(self.workoutRepository.observeRecent(limit: Self.recentLimit)) { $0.recent = $1 }
            }
            group.addTask {
                await self.follow(self.exerciseRepository.observeAll()) { store, all in
                    store.exercises = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
                }
            }
            group.addTask { await self.pump() }
            group.addTask { await self.haptic.run(haptics: self.haptics, clock: self.clock) }
        }
    }

    /// The session's workout, then every change, with its haptics (only from the stream, as on the phone, so a change
    /// is felt once). A stream that starts again forgets an answer kept from before, and the taps wait for its first
    /// update.
    func followSession() async {
        ahead = nil
        hasHeardSession = false
        defer { hasHeardSession = false }
        for await update in await session.updates() {
            show(update.state)
            haptic.enqueue(update.haptics)
            if !hasHeardSession {
                hasHeardSession = true
                wake?.yield()
            }
        }
    }

    /// Hears the live connection (F17 criterion 12): it sets only what the connection line reads.
    func followConnection() async {
        for await state in await liveConnection.states() {
            connection = state
            if state != .solo {
                hasHeardPhone = true
            }
        }
    }

    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        keep: @MainActor (WatchWorkoutStore, Value) -> Void
    ) async {
        for await value in values {
            keep(self, value)
        }
        if !Task.isCancelled {
            logger.log.error("A store's observation ended while the watch's workout was on screen")
        }
    }

    /// Shows `update`. Another workout starts afresh: no overlay and no dismissed summary. A change of mode closes the
    /// session list and leaves the end overlay (spec §4.2); a mode that is not live closes both.
    func show(_ update: WorkoutState?) {
        updatesHeard += 1
        // A finished workout stays (its summary until "Done"), though a stream that starts again opens on none.
        let next = update ?? (workout?.phase == .finished ? workout : nil)
        let before = mode
        if next?.id != workout?.id {
            overlay = nil
            isSummaryDismissed = false
            records = []
        }
        if let next, next.phase == .finished, workout?.phase != .finished || next.id != workout?.id {
            finishedShown?.yield(next)
        }
        workout = next
        ahead = ahead == next ? nil : ahead
        let isSameScreen = switch (before, mode) {
        case (.rest, .rest), (.restOver, .restOver): true // a rest "+30s" moved is still the rest screen
        default: before == mode
        }
        if !mode.isLive || (overlay == .list && !isSameScreen) {
            overlay = nil
        }
        crown.follow(live.flatMap(Self.crownReading))
        followRest()
    }

    /// What the crown reads in `state`: the set screen's set while it has one to log.
    static func crownReading(_ state: WorkoutState) -> CrownWeightModel.Reading? {
        guard let active = WatchPresentation.activeRow(of: state), let index = active.set else {
            return nil
        }
        let exercise = state.exercises[active.exercise], set = exercise.sets[index], units = state.units
        let step = SetEditing.step(of: exercise, loggedIn: units, readIn: units)
        let target = CrownWeightModel.Target(exerciseIndex: active.exercise, setID: set.id)
        return CrownWeightModel.Reading(target: target, weight: set.weight, step: step, units: units)
    }
}
