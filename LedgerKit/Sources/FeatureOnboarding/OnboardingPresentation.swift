import Foundation
import LedgerDesign
import LedgerDomain

/// One step of onboarding as the screen draws it: every string resolved, every control with the action it sends.
/// `OnboardingScreen` draws nothing else, so a preview, a snapshot and the VoiceOver test need only this.
nonisolated struct OnboardingStepModel: Equatable, Sendable {
    /// A button: its title and what it sends.
    nonisolated struct Control: Equatable, Sendable {
        let title: String
        let action: OnboardingAction
    }

    /// One pick of steps 1 and 2. VoiceOver reads it as one button, "{title}, {detail}", selected when picked.
    nonisolated struct Option: Equatable, Sendable, Identifiable {
        /// Its place in the list, from 0: what the UI tests' identifier ends in.
        let id: Int
        let title: String
        let detail: String
        let isSelected: Bool
        let action: OnboardingAction
    }

    /// One training day of step 3's list: read, not tapped.
    nonisolated struct Day: Equatable, Sendable, Identifiable {
        let id: Int
        /// "Upper A · Push focus".
        let title: String
        /// "Bench, incline, row, pulldown, laterals".
        let detail: String
    }

    nonisolated enum Content: Equatable, Sendable {
        case options([Option])
        case days([Day])
    }

    /// The three bars: orange up to this step.
    let progress: [ProgressSegment]
    /// What VoiceOver reads for the bars: "Step 1 of 3".
    let progressLabel: String
    let title: String
    let body: String
    let content: Content
    /// "Back": drawn on steps 2 and 3 (`showsBack`); on step 1 it only keeps its place, so the bars do not move.
    let back: Control
    let showsBack: Bool
    /// "Continue", "Start training" or, after a failed save, "Retry".
    let primary: Control
    let skip: Control
    /// The failure line, while the last save has failed.
    let error: String?
    /// Whether the options and "Back" answer: only while the lifter is picking.
    let canEdit: Bool
    /// Whether the primary button and "Skip setup" answer: not during a save, and not after it.
    let canProceed: Bool
}

/// Onboarding's presentation: a pure function from the state to the display model (M1 store convention). The
/// copy comes from `OnboardingCopy`; the program's name, its days and their lines are the Domain's
/// (`ProgramTemplates.preview(days:)`), shown as given but for the day names' " — ", drawn as " · ".
nonisolated enum OnboardingPresentation {
    static func make(_ state: OnboardingState, locale: Locale) -> OnboardingStepModel {
        let steps = OnboardingState.Step.allCases
        let isFailed = state.phase == .failed
        return OnboardingStepModel(
            progress: steps.map { step in
                ProgressSegment(length: 1, state: step.rawValue <= state.step.rawValue ? .current : .upcoming)
            },
            progressLabel: OnboardingCopy.step(state.step.rawValue + 1, of: steps.count, locale: locale),
            title: title(of: state.step),
            body: body(of: state, locale: locale),
            content: content(of: state),
            back: .init(title: OnboardingCopy.back, action: .back),
            showsBack: state.step != .goal,
            primary: primary(of: state),
            skip: .init(title: OnboardingCopy.skipSetup, action: .skipSetup),
            error: isFailed ? OnboardingCopy.saveFailed : nil,
            canEdit: state.phase == .editing,
            canProceed: state.phase == .editing || isFailed
        )
    }

    private static func title(of step: OnboardingState.Step) -> String {
        switch step {
        case .goal: OnboardingCopy.goalTitle
        case .days: OnboardingCopy.daysTitle
        case .program: OnboardingCopy.programTitle
        }
    }

    private static func body(of state: OnboardingState, locale: Locale) -> String {
        switch state.step {
        case .goal:
            return OnboardingCopy.goalBody
        case .days:
            return OnboardingCopy.daysBody
        case .program:
            let unit = OnboardingCopy.unitName(state.units)
            return OnboardingCopy.programBody(
                name: ProgramTemplates.preview(days: state.days).programName,
                weeks: ProgramTemplates.weekCount,
                unit: unit,
                locale: locale
            )
        }
    }

    private static func content(of state: OnboardingState) -> OnboardingStepModel.Content {
        switch state.step {
        case .goal:
            .options(TrainingGoal.allCases.enumerated().map { index, goal in
                .init(
                    id: index,
                    title: OnboardingCopy.title(of: goal),
                    detail: OnboardingCopy.detail(of: goal),
                    isSelected: goal == state.goal,
                    action: .pickGoal(goal)
                )
            })
        case .days:
            .options(DaysPerWeek.allCases.enumerated().map { index, days in
                .init(
                    id: index,
                    title: OnboardingCopy.title(of: days),
                    detail: OnboardingCopy.detail(of: days),
                    isSelected: days == state.days,
                    action: .pickDays(days)
                )
            })
        case .program:
            .days(ProgramTemplates.preview(days: state.days).days.enumerated().map { index, day in
                .init(id: index, title: day.name.replacing(" — ", with: " · "), detail: day.line)
            })
        }
    }

    /// A failed save turns the primary button into "Retry", and it stays so while the retry runs.
    private static func primary(of state: OnboardingState) -> OnboardingStepModel.Control {
        if state.phase == .failed || state.phase == .retrying {
            return .init(title: OnboardingCopy.retry, action: .retry)
        }
        return switch state.step {
        case .goal, .days: .init(title: OnboardingCopy.continueTitle, action: .advance)
        case .program: .init(title: OnboardingCopy.startTraining, action: .startTraining)
        }
    }
}
