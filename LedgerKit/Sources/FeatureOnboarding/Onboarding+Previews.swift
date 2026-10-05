#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureOnboarding, one case each: the states of the screen, drawn from the model the
    /// presentation makes of a state. `PreviewTests` render every case and fail on a `#Preview` that is not a
    /// case here; `OnboardingSnapshotTests` and `OnboardingAccessibilityTests` draw the same cases. None runs a
    /// task: the screen only draws, and `OnboardingRoot`, which loads and saves, has no preview.
    enum OnboardingPreview: String, CaseIterable {
        case goal = "Step 1, goal"
        case days = "Step 2, days"
        case program = "Step 3, four days"
        case programSixDays = "Step 3, six days"
        case saving = "Step 3, saving"
        case failed = "Step 3, save failed"

        /// The state the case shows.
        var state: OnboardingState {
            switch self {
            case .goal: OnboardingState()
            case .days: OnboardingState(step: .days)
            case .program: OnboardingState(step: .program)
            case .programSixDays: OnboardingState(step: .program, days: .six)
            case .saving: OnboardingState(step: .program, phase: .saving)
            case .failed: OnboardingState(step: .program, phase: .failed)
            }
        }

        var content: some View {
            OnboardingScreen(model: OnboardingPresentation.make(state, locale: Fixtures.locale)) { _ in }
        }
    }

    #Preview("Step 1, goal") {
        OnboardingPreview.goal.content
    }

    #Preview("Step 2, days") {
        OnboardingPreview.days.content
    }

    #Preview("Step 3, four days") {
        OnboardingPreview.program.content
    }

    #Preview("Step 3, six days") {
        OnboardingPreview.programSixDays.content
    }

    #Preview("Step 3, saving") {
        OnboardingPreview.saving.content
    }

    #Preview("Step 3, save failed") {
        OnboardingPreview.failed.content
    }

#endif
