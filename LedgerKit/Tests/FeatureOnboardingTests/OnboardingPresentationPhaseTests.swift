@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criteria 7 and 9, in the display model: what each phase of the save shows and lets the lifter do, and
/// the two rules every string keeps (none names the product; numbers follow the locale given).
@Suite("OnboardingPresentation: phases and copy rules", .tags(.feature))
nonisolated struct OnboardingPresentationPhaseTests {
    typealias Tests = OnboardingPresentationTests
    typealias Step = OnboardingState.Step
    typealias Phase = OnboardingState.Phase

    // MARK: Phases

    @Test(
        "Only a failed save shows the sentence, and it turns the primary button into Retry on every step",
        arguments: Step.allCases
    )
    func failed_showsTheSentenceAndRetry(on step: Step) {
        let model = Tests.model(OnboardingState(step: step, phase: .failed))
        #expect(model.error == "Couldn't save your program. Try again.")
        #expect(model.primary == .init(title: "Retry", action: .retry))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(model.canProceed)
        #expect(!model.canEdit)
        for phase in Tests.phases where phase != .failed {
            #expect(Tests.model(OnboardingState(step: step, phase: phase)).error == nil)
        }
    }

    @Test("While a retry runs the button still reads Retry, and nothing answers")
    func retrying_keepsRetry_andLocksEverything() {
        let model = Tests.model(OnboardingState(step: .program, phase: .retrying))
        #expect(model.primary == .init(title: "Retry", action: .retry))
        #expect(!model.canProceed && !model.canEdit)
    }

    @Test("During a save and after it nothing answers; the step is drawn as it was", arguments: [Phase.saving, .saved])
    func savingAndSaved_lockEverything(_ phase: Phase) {
        for step in Step.allCases {
            let editing = Tests.model(OnboardingState(step: step))
            let model = Tests.model(OnboardingState(step: step, phase: phase))
            #expect(!model.canProceed && !model.canEdit)
            #expect(model.primary == editing.primary)
            #expect(model.content == editing.content)
            #expect(model.title == editing.title)
        }
    }

    // MARK: Copy rules

    @Test("No string of any state names the product")
    func noString_namesTheProduct() {
        for step in Step.allCases {
            for phase in Tests.phases {
                for days in DaysPerWeek.allCases {
                    let model = Tests.model(OnboardingState(step: step, days: days, units: .kg, phase: phase))
                    let named = Tests.strings(of: model).filter { $0.localizedCaseInsensitiveContains("ledger") }
                    #expect(named.isEmpty)
                }
            }
        }
    }

    @Test("Numbers are formatted in the locale the presentation is given")
    func numbers_followTheLocale() {
        let arabicDigits = Locale(identifier: "en_US@numbers=arab")
        let model = OnboardingPresentation.make(OnboardingState(step: .program), locale: arabicDigits)
        #expect(model.progressLabel == "Step ٣ of ٣")
        #expect(model.body == "Upper / Lower, ٨ weeks, pounds. Editable any time.")
    }
}
