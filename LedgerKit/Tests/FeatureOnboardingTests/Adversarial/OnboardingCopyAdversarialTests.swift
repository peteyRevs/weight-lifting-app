@testable import FeatureOnboarding
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2 adversarial round 1, criteria 1 to 3 and 9: every text of every step and state against the brief's
/// "Copy (exact)", character for character. The expected texts are typed from the brief (`BriefCopy`); the
/// program names, day names and lines are the Domain's data.
@Suite("Adversarial F08 S2 · every text of every step and state")
struct OnboardingCopyAdversarialTests {
    typealias Step = OnboardingState.Step

    nonisolated static let phases: [OnboardingState.Phase] = [.editing, .saving, .failed, .retrying, .saved]

    static func model(
        _ step: Step,
        goal: TrainingGoal = .both,
        days: DaysPerWeek = .four,
        units: Units = .lb,
        phase: OnboardingState.Phase = .editing
    ) -> OnboardingStepModel {
        let state = OnboardingState(step: step, goal: goal, days: days, units: units, phase: phase)
        return OnboardingPresentation.make(state, locale: Fixtures.locale)
    }

    /// Every text a model holds.
    static func texts(of model: OnboardingStepModel) -> [String] {
        var texts = [model.progressLabel, model.title, model.body, model.primary.title, model.skip.title]
        texts += model.showsBack ? [model.back.title] : []
        texts += model.error.map { [$0] } ?? []
        switch model.content {
        case let .options(options): texts += options.flatMap { [$0.title, $0.detail] }
        case let .days(days): texts += days.flatMap { [$0.title, $0.detail] }
        }
        return texts
    }

    /// Every model the screen can draw: each step, pick, unit and phase.
    static var everyModel: [OnboardingStepModel] {
        Step.allCases.flatMap { step in
            TrainingGoal.allCases.flatMap { goal in
                DaysPerWeek.allCases.flatMap { days in
                    Units.allCases.flatMap { units in
                        phases.map { model(step, goal: goal, days: days, units: units, phase: $0) }
                    }
                }
            }
        }
    }

    @Test("Step 1 opens on Both, honestly with the brief's title, line, four options, Continue and Skip setup")
    func stepOne_default_isTheBriefs() {
        let model = OnboardingPresentation.make(OnboardingState(), locale: Fixtures.locale)
        #expect(model.progressLabel == "Step 1 of 3")
        #expect(model.title == "What are you training for?")
        #expect(model.body == "This sets how your loads progress week to week.")
        #expect(model.primary == .init(title: "Continue", action: .advance))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(!model.showsBack)
        #expect(model.error == nil)
        #expect(model.canEdit && model.canProceed)
        guard case let .options(options) = model.content else {
            Issue.record("step 1 draws options")
            return
        }
        #expect(options.map(\.title) == ["Get stronger", "Build muscle", "Both, honestly", "Stay consistent"])
        #expect(options.map(\.detail) == BriefCopy.goals.map(\.detail))
        #expect(options.map(\.isSelected) == [false, false, true, false])
        #expect(options.map(\.action) == BriefCopy.goals.map { .pickGoal($0.goal) })
        #expect(options.map(\.id) == [0, 1, 2, 3])
    }

    @Test("Step 1 ticks exactly the picked goal, whatever the phase", arguments: TrainingGoal.allCases, phases)
    func stepOne_everyGoal_ticksOnlyIt(goal: TrainingGoal, phase: OnboardingState.Phase) {
        let model = Self.model(.goal, goal: goal, phase: phase)
        guard case let .options(options) = model.content else {
            Issue.record("step 1 draws options")
            return
        }
        #expect(options.map(\.isSelected) == BriefCopy.goals.map { $0.goal == goal })
        #expect(options.map(\.title) == BriefCopy.goals.map(\.title))
        #expect(model.title == BriefCopy.goalTitle)
        #expect(model.body == BriefCopy.goalBody)
    }

    @Test(
        "Step 2 has the brief's title, line and four options, ticks the picked one, and has Back",
        arguments: DaysPerWeek.allCases
    )
    func stepTwo_everyPick_isTheBriefs(days: DaysPerWeek) {
        let model = Self.model(.days, days: days)
        #expect(model.progressLabel == "Step 2 of 3")
        #expect(model.title == "How many days a week?")
        #expect(model.body == "Pick the number you will actually hit, not the one you want to hit.")
        #expect(model.primary == .init(title: "Continue", action: .advance))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(model.back == .init(title: "Back", action: .back))
        #expect(model.showsBack)
        guard case let .options(options) = model.content else {
            Issue.record("step 2 draws options")
            return
        }
        #expect(options.map(\.title) == ["3 days", "4 days", "5 days", "6 days"])
        #expect(options.map(\.detail) == [
            "Full body each session", "Upper / lower split", "Push, pull, legs + accessories", "Body-part split"
        ])
        #expect(options.map(\.isSelected) == DaysPerWeek.allCases.map { $0 == days })
        #expect(options.map(\.action) == DaysPerWeek.allCases.map(OnboardingAction.pickDays))
    }

    @Test(
        "Step 3 lists every day of the split as the Domain names it, with the brief's sentence in each unit",
        arguments: DaysPerWeek.allCases,
        Units.allCases
    )
    func stepThree_everySplitAndUnit_isTheBriefs(days: DaysPerWeek, units: Units) {
        let model = Self.model(.program, goal: .strength, days: days, units: units)
        #expect(model.progressLabel == "Step 3 of 3")
        #expect(model.title == "Your program")
        #expect(model.body == BriefCopy.programBody(days, units))
        #expect(model.primary == .init(title: "Start training", action: .startTraining))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(model.back == .init(title: "Back", action: .back))
        #expect(model.showsBack)
        guard case let .days(rows) = model.content else {
            Issue.record("step 3 draws the program's days, not options")
            return
        }
        let expected = BriefCopy.dayRows(days)
        #expect(rows.map(\.title) == expected.map(\.title))
        #expect(rows.map(\.detail) == expected.map(\.detail))
        #expect(rows.count == days.rawValue)
        #expect(rows.allSatisfy { !$0.title.contains("—") })
    }

    @Test("The default program's sentence and rows are spec §6.7's, with Lower B as the brief corrects it")
    func stepThree_fourDays_isSpelledAsTheBrief() {
        let model = Self.model(.program)
        #expect(model.body == "Upper / Lower, 8 weeks, pounds. Editable any time.")
        #expect(Self.model(.program, units: .kg).body == "Upper / Lower, 8 weeks, kilograms. Editable any time.")
        guard case let .days(rows) = model.content else {
            Issue.record("step 3 draws the program's days")
            return
        }
        #expect(rows.map(\.title) == BriefCopy.fourDayRows.map(\.title))
        #expect(rows.map(\.detail) == BriefCopy.fourDayRows.map(\.detail))
    }
}

/// The failure state, the bars, the whole set of texts, the locale and the String Catalog.
extension OnboardingCopyAdversarialTests {
    @Test("A failed save shows the brief's sentence and Retry on whichever step it happened", arguments: Step.allCases)
    func failed_everyStep_showsTheSentenceAndRetry(step: Step) {
        let model = Self.model(step, phase: .failed)
        #expect(model.error == "Couldn't save your program. Try again.")
        #expect(model.primary == .init(title: "Retry", action: .retry))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(model.canProceed)
        for phase in [OnboardingState.Phase.editing, .saving, .saved] {
            #expect(Self.model(step, phase: phase).error == nil, "\(phase)")
        }
    }

    @Test("The bars are three equal segments, orange up to the step and a track after it", arguments: Step.allCases)
    func progress_everyStep_isOrangeUpToIt(step: Step) {
        let model = Self.model(step)
        let orange = Array(repeating: ProgressSegment.State.current, count: step.rawValue + 1)
        let track = Array(repeating: ProgressSegment.State.upcoming, count: 2 - step.rawValue)
        #expect(model.progress.map(\.state) == orange + track, "only `.current` is drawn in the accent")
        #expect(Set(model.progress.map(\.length)).count == 1)
        #expect(model.progress.allSatisfy { $0.length > 0 })
    }

    @Test("No text of any step, pick, unit or phase names the product, and none is outside the brief or the Domain")
    func everyModel_namesNoProductAndInventsNothing() {
        var known: Set = [
            BriefCopy.goalTitle, BriefCopy.goalBody, BriefCopy.daysTitle, BriefCopy.daysBody, BriefCopy.programTitle,
            BriefCopy.continueTitle, BriefCopy.startTraining, BriefCopy.skipSetup, BriefCopy.back, BriefCopy.retry,
            BriefCopy.saveFailed, "Step 1 of 3", "Step 2 of 3", "Step 3 of 3"
        ]
        known.formUnion(BriefCopy.goals.flatMap { [$0.title, $0.detail] })
        known.formUnion(BriefCopy.days.flatMap { [$0.title, $0.detail] })
        for days in DaysPerWeek.allCases {
            known.formUnion(BriefCopy.dayRows(days).flatMap { [$0.title, $0.detail] })
            known.formUnion(Units.allCases.map { BriefCopy.programBody(days, $0) })
        }
        let drawn = Set(Self.everyModel.flatMap(Self.texts))
        #expect(drawn.subtracting(known).isEmpty, "\(drawn.subtracting(known).sorted())")
        #expect(drawn.allSatisfy { !$0.localizedCaseInsensitiveContains("ledger") })
        #expect(drawn.allSatisfy { !$0.isEmpty })
    }

    @Test("Numbers follow the injected locale: Arabic digits in the step and the weeks, not the device's")
    func locale_arabic_formatsTheNumbers() {
        let arabic = Locale(identifier: "ar_SA")
        let state = OnboardingState(step: .program, days: .six, units: .kg)
        let model = OnboardingPresentation.make(state, locale: arabic)
        #expect(model.progressLabel == String(format: "Step %lld of %lld", locale: arabic, 3, 3))
        let body = String(
            format: "%@, %lld weeks, %@. Editable any time.",
            locale: arabic,
            "Body-Part Split",
            8,
            "kilograms"
        )
        #expect(model.body == body)
        #expect(model.progressLabel != "Step 3 of 3", "control: the locale changes the digits")
        var setup = AdversarialScene.Setup(seed: .empty)
        setup.locale = arabic
        let scene = AdversarialScene(setup)
        #expect(scene.store.model.progressLabel == String(format: "Step %lld of %lld", locale: arabic, 1, 3))
    }

    @Test("The String Catalog holds the brief's texts and nothing else, each translated as its key")
    func catalog_keys_areTheBriefs() throws {
        let catalog = try StringCatalog(module: "FeatureOnboarding")
        var expected: Set = [
            BriefCopy.goalTitle, BriefCopy.goalBody, BriefCopy.daysTitle, BriefCopy.daysBody, BriefCopy.programTitle,
            BriefCopy.continueTitle, BriefCopy.startTraining, BriefCopy.skipSetup, BriefCopy.back, BriefCopy.retry,
            BriefCopy.saveFailed, "%@, %lld weeks, %@. Editable any time.", "pounds", "kilograms",
            "Step %lld of %lld"
        ]
        expected.formUnion(BriefCopy.goals.flatMap { [$0.title, $0.detail] })
        expected.formUnion(BriefCopy.days.flatMap { [$0.title, $0.detail] })
        #expect(
            catalog.keys.subtracting(expected).isEmpty,
            "not in the brief: \(catalog.keys.subtracting(expected).sorted())"
        )
        #expect(expected.subtracting(catalog.keys).isEmpty, "missing: \(expected.subtracting(catalog.keys).sorted())")
        #expect(catalog.problems.isEmpty, "\(catalog.problems)")
        #expect(catalog.keys.allSatisfy { !$0.localizedCaseInsensitiveContains(StringCatalog.productName) })
    }
}
