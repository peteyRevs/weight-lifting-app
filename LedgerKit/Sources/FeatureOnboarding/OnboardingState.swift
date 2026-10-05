import LedgerDomain

/// Everything the onboarding screen shows, as one value: `OnboardingPresentation.make` turns it into the display
/// model, and `OnboardingStore` is the only thing that changes it.
nonisolated struct OnboardingState: Equatable, Sendable {
    /// The three steps, in order.
    nonisolated enum Step: Int, CaseIterable, Sendable {
        case goal, days, program

        /// The step after this one; the last step is its own next.
        var next: Step {
            Step(rawValue: rawValue + 1) ?? self
        }

        /// The step before this one; the first step is its own previous.
        var previous: Step {
            Step(rawValue: rawValue - 1) ?? self
        }
    }

    /// Where the screen stands between picking and the saved program.
    nonisolated enum Phase: Sendable {
        /// The lifter is picking: every control answers.
        case editing
        /// "Start training" or "Skip setup" was tapped; the program is being written.
        case saving
        /// The last attempt failed: the screen says so and offers "Retry".
        case failed
        /// A tap after a failure: the root's `prepareRetry` runs first, then the program is written.
        case retrying
        /// The program is saved and active. Nothing more happens here; the app's root follows the active program.
        case saved

        /// Whether a save is under way: nothing answers until it ends.
        var isSaving: Bool {
            self == .saving || self == .retrying
        }
    }

    var step = Step.goal
    var goal = TrainingGoal.both
    var days = DaysPerWeek.four
    /// The unit the stored settings name; the default's until they are read.
    var units = Settings.default.units
    var phase = Phase.editing
}

/// What the lifter can do on the screen. The display model names the action of each control, the screen sends
/// it back, and `OnboardingStore.send` is the one place that decides what it changes.
nonisolated enum OnboardingAction: Hashable, Sendable {
    case pickGoal(TrainingGoal)
    case pickDays(DaysPerWeek)
    /// "Continue".
    case advance
    case back
    /// "Start training": save the program the picks give.
    case startTraining
    /// "Skip setup": save the default program (`both`, four days), whatever is picked.
    case skipSetup
    /// "Retry": the failed attempt again, with what it was asked for.
    case retry
}

/// One accepted tap on "Start training", "Skip setup" or "Retry": the save the root's `.task(id:)` runs.
///
/// Each accepted tap makes the next one, so the task's id changes exactly when there is a new save to run. It
/// holds what was asked for at the tap, which is how "Retry" writes the same program as the attempt that failed,
/// also after a failed "Skip setup".
nonisolated struct OnboardingSaveAttempt: Hashable, Sendable {
    let number: Int
    let goal: TrainingGoal
    let days: DaysPerWeek
}
