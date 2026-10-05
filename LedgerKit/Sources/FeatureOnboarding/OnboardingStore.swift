import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// Why a save could not start writing, beyond what the stores and the generator throw themselves.
nonisolated enum OnboardingError: Error, Equatable {
    /// The week that holds the injected date starts outside the years a `CivilDate` can name.
    case startDateOutOfRange
}

/// Onboarding's store (M1 store convention): the screen's state, the intents that change it, and the one piece
/// of asynchronous work, saving the program.
///
/// Intents are synchronous and only change state. The store starts no task: `OnboardingRoot` runs `loadUnits()`
/// and `save(prepareRetry:)` from its `.task`s, so nothing here outlives the view. Dependencies are read where
/// the store is made (in the app, the values the composition root prepared; in a test, those of the
/// `withTestDependencies` the store was built in), and they stay the store's for its life.
///
/// **One program.** A tap on "Start training", "Skip setup" or "Retry" is accepted only while no save is under
/// way and none has succeeded; an accepted tap makes the next `attempt`, which is the id of the root's task.
/// `save` runs an attempt once: it returns at once unless the phase says a save is due, and a second call that
/// arrives while one is running does nothing. The program is written by one `ProgramRepository.save`, which
/// writes all of it or nothing.
@MainActor @Observable
final class OnboardingStore {
    private(set) var state = OnboardingState()
    /// The save the root's `.task(id:)` runs; nil until the first accepted tap.
    private(set) var attempt: OnboardingSaveAttempt?
    @ObservationIgnored private var isSaveRunning = false

    @ObservationIgnored @Dependency(\.programRepository) private var programs
    @ObservationIgnored @Dependency(\.exerciseRepository) private var exercises
    @ObservationIgnored @Dependency(\.settingsRepository) private var settings
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    private var logger: LedgerLogger {
        injectedLogger.category("onboarding")
    }

    /// What the screen draws.
    var model: OnboardingStepModel {
        OnboardingPresentation.make(state, locale: locale)
    }

    // MARK: Intents

    func send(_ action: OnboardingAction) {
        switch action {
        case let .pickGoal(goal):
            edit { $0.goal = goal }
        case let .pickDays(days):
            edit { $0.days = days }
        case .advance:
            edit { $0.step = $0.step.next }
        case .back:
            edit { $0.step = $0.step.previous }
        case .startTraining:
            if state.phase == .editing {
                begin(goal: state.goal, days: state.days)
            }
        case .skipSetup:
            begin(goal: .both, days: .four)
        case .retry:
            if state.phase == .failed, let attempt {
                begin(goal: attempt.goal, days: attempt.days)
            }
        }
    }

    /// Picks and steps change only while the lifter is picking: not during a save, not after it, and not while
    /// a failed attempt waits for its retry (the attempt holds what it was asked for).
    private func edit(_ change: (inout OnboardingState) -> Void) {
        guard state.phase == .editing else {
            return
        }
        change(&state)
    }

    /// Accepts a save for `goal` and `days`, unless one is under way or has succeeded. After a failure the next
    /// one is a retry, which prepares first.
    private func begin(goal: TrainingGoal, days: DaysPerWeek) {
        guard state.phase == .editing || state.phase == .failed else {
            return
        }
        attempt = OnboardingSaveAttempt(number: (attempt?.number ?? 0) + 1, goal: goal, days: days)
        state.phase = state.phase == .failed ? .retrying : .saving
    }

    // MARK: Work the root's tasks run

    /// Reads the stored unit, for step 3's sentence. If the settings cannot be read the default's unit stays and
    /// the failure is logged; the save reads them again and fails where the lifter can see it. A read that was
    /// cancelled, because the view went away, is no failure and logs nothing.
    func loadUnits() async {
        do {
            state.units = try await settings.load().units
        } catch is CancellationError {
            return
        } catch {
            logger.log.error("Onboarding could not read the settings: \(String(describing: error), privacy: .public)")
        }
    }

    /// Runs the current attempt: writes the program it asks for, from the stored settings and catalog, and makes
    /// it the active one. A retry awaits `prepareRetry` first (the launch's seed step: an unseeded catalog is why
    /// a first launch's save fails, product decision #28).
    ///
    /// Any failure (the settings, the catalog, the generator, the save) is logged and leaves `.failed`, with
    /// nothing saved. A save cancelled before its write, because the view went away, writes nothing and leaves
    /// the phase as it was before the tap, so the same tap works again if the view returns. A cancellation is
    /// not a failure: it is neither shown nor logged as one. A real failure that arrives on a cancelled task is
    /// still logged, though the view that would show it is gone. Once the repository has saved, the phase is
    /// `.saved` whether or not the task was cancelled meanwhile.
    func save(prepareRetry: @MainActor () async -> Void) async {
        guard let attempt, state.phase.isSaving, !isSaveRunning else {
            return
        }
        isSaveRunning = true
        defer { isSaveRunning = false }
        let isRetry = state.phase == .retrying
        do {
            if isRetry {
                await prepareRetry()
            }
            let program = try await program(for: attempt)
            try Task.checkCancellation()
            try await programs.save(program)
            state.phase = .saved
        } catch {
            if !(error is CancellationError) {
                let reason = String(describing: error)
                logger.log.error("Onboarding could not save the program: \(reason, privacy: .public)")
            }
            guard !Task.isCancelled else {
                state.phase = isRetry ? .failed : .editing
                return
            }
            state.phase = .failed
        }
    }

    /// The program `attempt` asks for, in the stored settings' unit, starting on the first day (per the
    /// settings' week start) of the week that holds the injected date, over the stored catalog.
    private func program(for attempt: OnboardingSaveAttempt) async throws -> Program {
        let stored = try await settings.load()
        state.units = stored.units
        let catalog = try await exercises.all()
        let now = date.now
        guard let start = ProgramTemplates.startDate(containing: now, weekStart: stored.weekStart, calendar: calendar)
        else {
            throw OnboardingError.startDateOutOfRange
        }
        let request = ProgramTemplates.Request(
            goal: attempt.goal,
            days: attempt.days,
            units: stored.units,
            startDate: start
        )
        return try ProgramTemplates.program(request, catalog: catalog, id: ProgramID(uuid()), newID: { uuid() })
    }
}
