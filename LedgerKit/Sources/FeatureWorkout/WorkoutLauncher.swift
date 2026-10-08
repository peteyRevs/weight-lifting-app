import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// Which workout is showing: the one presenter of the workout's cover (architecture §4). The app's root holds
/// one for its life, applies `View.workoutCover(_:onRoute:)` above the tabs, and calls `start(_:)` and
/// `resume()` when Today asks.
///
/// **Intents are synchronous and only change state** (M1 store convention). An accepted intent makes the next
/// `request`, which is the id of the cover modifier's task; `run()` answers it from that task, so the
/// launcher starts no task and nothing here outlives the view. Making a launcher does no work and reads no
/// dependency: the keys are first read when a request is answered, by which time the database is open.
///
/// **One workout live, or none.** A request is accepted only while nothing is under way and the cover is
/// down, so two taps start one workout. A live workout is shown from the session's own state and never
/// through `StartWorkoutUseCase` (F10 S4 criterion 3): the use case refuses a day that was since emptied or
/// deleted, and a workout that is running must still be reachable. The use case is asked only when nothing
/// is live or another day is asked for. It owns the order of "Discard and start new": the new session is
/// built first, the live workout is discarded only then, and the new one starts only when that discard went
/// through. After a failure the launcher reads the session again and says what it holds, rather than
/// inferring it from the error.
@MainActor @Observable
public final class WorkoutLauncher {
    private(set) var phase = WorkoutLaunchPhase.idle
    /// The work the cover modifier's `.task(id:)` runs; nil until the first accepted intent.
    private(set) var request: WorkoutLaunchRequest?
    @ObservationIgnored private var isRunning = false

    @ObservationIgnored @Dependency(\.workoutSession) private var session
    @ObservationIgnored @Dependency(\.programRepository) private var programs
    @ObservationIgnored @Dependency(\.exerciseRepository) private var exercises
    @ObservationIgnored @Dependency(\.statsQueries) private var stats
    @ObservationIgnored @Dependency(\.settingsRepository) private var settings
    @ObservationIgnored @Dependency(\.deviceID) private var device
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    public init() {}

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    private var logger: LedgerLogger {
        injectedLogger.category("workout")
    }

    // MARK: Intents

    /// "Start workout" for a week and day of the active program: opens the cover on that day's workout, new
    /// or already running, or asks what to do about another day's workout that is live.
    public func start(_ source: WorkoutSource) {
        accept(.start(source))
    }

    /// "Resume": opens the cover on the live workout. With none live it does nothing.
    public func resume() {
        accept(.resume)
    }

    func send(_ action: WorkoutLaunchAction) {
        switch action {
        case .resumeLive:
            accept(.resume)
        case let .replaceLive(source):
            accept(.replace(source))
        case .cancelConflict:
            if case .conflict = phase {
                phase = .idle
            }
        case .dismissFailure:
            if case .failed = phase {
                phase = .idle
            }
        case .coverClosed:
            if phase == .cover {
                phase = .idle
            }
        }
    }

    /// Accepts `job` unless a request is being answered or the cover is up. A dialog that is showing does not
    /// stand in the way: its own choices arrive here, in either order with its dismissal.
    func accept(_ job: WorkoutLaunchRequest.Job) {
        guard phase != .working, phase != .cover else {
            return
        }
        request = WorkoutLaunchRequest(number: (request?.number ?? 0) + 1, job: job)
        phase = .working
    }

    // MARK: Work the cover modifier's task runs

    /// Answers the current request, once: it returns at once unless one is due, and a second call that
    /// arrives while one is running does nothing.
    ///
    /// A request cancelled because the view went away is not a failure: it is neither shown nor logged as
    /// one, and the launcher is `idle` again unless the work had already gone through. On a host that
    /// completes each call in a task of its own, as the app's does, a cancelled request leaves no workout
    /// half started and none half replaced.
    func run() async {
        guard let request, phase == .working, !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }
        do {
            phase = try await answer(request.job)
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                phase = .idle
                return
            }
            logger.log.error("The workout could not be opened: \(String(describing: error), privacy: .public)")
            phase = await phase(afterFailing: request.job, error)
        }
    }

    private func answer(_ job: WorkoutLaunchRequest.Job) async throws -> WorkoutLaunchPhase {
        switch job {
        case .resume:
            return try await session.current() == nil ? .idle : .cover
        case let .start(source):
            if let live = try await session.current(), live.source == source {
                return .cover
            }
            return try await phase(after: useCase.start(source), asking: source)
        case let .replace(source):
            return try await phase(after: useCase.start(source, replacingLive: true), asking: source)
        #if DEBUG
            case let .sample(day):
                return try await answer(.start(WorkoutSample.source(day: day, in: programs)))
        #endif
        }
    }

    private func phase(after outcome: StartWorkoutUseCase.Outcome, asking source: WorkoutSource) -> WorkoutLaunchPhase {
        switch outcome {
        case .started, .resumed: .cover
        case .conflict: .conflict(source)
        }
    }

    /// Where a request that threw leaves the launcher. What the session holds now decides it, not the
    /// error: the workout that was asked for, live after all (a write went through and its answer was
    /// lost), opens the cover; after a replacement that failed, the old workout is still live or nothing is.
    private func phase(afterFailing job: WorkoutLaunchRequest.Job, _ error: any Error) async -> WorkoutLaunchPhase {
        var aftermath = WorkoutLaunchFailure.Aftermath.unknown
        var asked: WorkoutSource?
        if case let .start(source) = job {
            asked = source
        } else if case let .replace(source) = job {
            asked = source
        }
        do {
            let live = try await session.current()
            if let live, let asked, live.source == asked {
                return .cover
            }
            aftermath = live == nil ? .nothingLive : .liveKept
        } catch {
            logger.log.error("The session could not be read: \(String(describing: error), privacy: .public)")
        }
        let reason = Self.reason(error)
        switch job {
        case .resume:
            return aftermath == .liveKept ? .cover : .failed(.notOpened)
        case .replace where reason == .other:
            return .failed(.notReplaced(aftermath))
        default:
            // A replacement refused for a reason the lifter can act on says why, as a plain start does,
            // whatever the session shows or fails to show afterwards: each such refusal is thrown before
            // anything is discarded. "Nothing was changed" is said only when the session was read.
            return .failed(.notStarted(reason == .other && aftermath == .unknown ? .unknown : reason))
        }
    }

    private static func reason(_ error: any Error) -> WorkoutLaunchFailure.Reason {
        switch error {
        case StartWorkoutError.emptyDay: .emptyDay
        case StartWorkoutError.programNotActive, StartWorkoutError.dayNotInProgram: .dayNotInProgram
        case SessionBuilderError.weekOutOfRange: .blockEnded
        default: .other
        }
    }

    /// "Start workout" over the stores and the session as they are bound now.
    private var useCase: StartWorkoutUseCase {
        StartWorkoutUseCase(
            session: session,
            programs: programs,
            exercises: exercises,
            stats: stats,
            settings: settings,
            device: device,
            now: { [date] in date.now },
            newID: { [uuid] in uuid() }
        )
    }
}
