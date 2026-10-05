@testable import FeatureOnboarding
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criteria 1, 2, 3, 6 and 9, in the display model: each step's copy against product spec §6.7 (with the
/// brief's wording of step 1's body), the pick that is selected, step 3's read-only days, and what each phase
/// lets the lifter do. The presentation is a pure function, so every case is a state and its model.
@Suite("OnboardingPresentation")
nonisolated struct OnboardingPresentationTests {
    typealias Step = OnboardingState.Step
    typealias Phase = OnboardingState.Phase

    static let phases: [Phase] = [.editing, .saving, .failed, .retrying, .saved]

    static func model(_ state: OnboardingState) -> OnboardingStepModel {
        OnboardingPresentation.make(state, locale: Fixtures.locale)
    }

    static func options(_ state: OnboardingState) -> [OnboardingStepModel.Option] {
        guard case let .options(options) = model(state).content else {
            return []
        }
        return options
    }

    static func days(_ days: DaysPerWeek) -> [OnboardingStepModel.Day] {
        guard case let .days(rows) = model(OnboardingState(step: .program, days: days)).content else {
            return []
        }
        return rows
    }

    /// Every string a model shows or speaks.
    static func strings(of model: OnboardingStepModel) -> [String] {
        var strings = [model.progressLabel, model.title, model.body, model.back.title, model.primary.title]
        strings += [model.skip.title, model.error ?? ""]
        switch model.content {
        case let .options(options): strings += options.flatMap { [$0.title, $0.detail] }
        case let .days(days): strings += days.flatMap { [$0.title, $0.detail] }
        }
        return strings
    }

    // MARK: Step 1

    @Test("Step 1 asks what the lifter trains for, with the four goals and Both picked")
    func step1_isTheSpecsCopy_withBothPicked() {
        let model = Self.model(OnboardingState())
        #expect(model.title == "What are you training for?")
        #expect(model.body == "This sets how your loads progress week to week.")
        #expect(model.progressLabel == "Step 1 of 3")
        #expect(model.progress == [
            ProgressSegment(length: 1, state: .current),
            ProgressSegment(length: 1, state: .upcoming),
            ProgressSegment(length: 1, state: .upcoming)
        ])
        #expect(model.primary == .init(title: "Continue", action: .advance))
        #expect(model.skip == .init(title: "Skip setup", action: .skipSetup))
        #expect(!model.showsBack)
        #expect(model.error == nil)
        #expect(model.canEdit && model.canProceed)

        let options = Self.options(OnboardingState())
        #expect(options.map(\.id) == [0, 1, 2, 3])
        #expect(options.map(\.title) == ["Get stronger", "Build muscle", "Both, honestly", "Stay consistent"])
        #expect(options.map(\.detail) == [
            "Low reps, linear load increases",
            "Moderate reps, volume tracking",
            "Barbell strength + accessory volume",
            "Habit first, numbers second"
        ])
        #expect(options.map(\.isSelected) == [false, false, true, false])
        #expect(options.map(\.action) == [
            .pickGoal(.strength), .pickGoal(.hypertrophy), .pickGoal(.both), .pickGoal(.consistency)
        ])
    }

    @Test("Exactly the picked goal is selected", arguments: TrainingGoal.allCases)
    func step1_selectsOnlyThePick(_ goal: TrainingGoal) {
        let options = Self.options(OnboardingState(goal: goal))
        #expect(options.filter(\.isSelected).map(\.action) == [.pickGoal(goal)])
    }

    // MARK: Step 2

    @Test("Step 2 asks how many days, with the four splits and 4 days picked")
    func step2_isTheSpecsCopy_withFourDaysPicked() {
        let state = OnboardingState(step: .days)
        let model = Self.model(state)
        #expect(model.title == "How many days a week?")
        #expect(model.body == "Pick the number you will actually hit, not the one you want to hit.")
        #expect(model.progressLabel == "Step 2 of 3")
        #expect(model.progress.map(\.state) == [.current, .current, .upcoming])
        #expect(model.primary == .init(title: "Continue", action: .advance))
        #expect(model.back == .init(title: "Back", action: .back))
        #expect(model.showsBack)

        let options = Self.options(state)
        #expect(options.map(\.title) == ["3 days", "4 days", "5 days", "6 days"])
        #expect(options.map(\.detail) == [
            "Full body each session", "Upper / lower split", "Push, pull, legs + accessories", "Body-part split"
        ])
        #expect(options.map(\.isSelected) == [false, true, false, false])
        #expect(options.map(\.action) == [.pickDays(.three), .pickDays(.four), .pickDays(.five), .pickDays(.six)])
    }

    @Test("Exactly the picked number of days is selected", arguments: DaysPerWeek.allCases)
    func step2_selectsOnlyThePick(_ days: DaysPerWeek) {
        let options = Self.options(OnboardingState(step: .days, days: days))
        #expect(options.filter(\.isSelected).map(\.action) == [.pickDays(days)])
    }

    // MARK: Step 3

    @Test("Step 3 lists the four-day program's days, in order, as spec §6.7 words them")
    func step3_fourDays_listsTheProgram() {
        let model = Self.model(OnboardingState(step: .program))
        #expect(model.title == "Your program")
        #expect(model.body == "Upper / Lower, 8 weeks, pounds. Editable any time.")
        #expect(model.progressLabel == "Step 3 of 3")
        #expect(model.progress.map(\.state) == [.current, .current, .current])
        #expect(model.primary == .init(title: "Start training", action: .startTraining))
        #expect(model.showsBack)

        let rows = Self.days(.four)
        #expect(rows.map(\.id) == [0, 1, 2, 3])
        #expect(rows.map(\.title) == [
            "Upper A · Push focus", "Lower A · Squat focus", "Upper B · Pull focus", "Lower B · Hinge focus"
        ])
        #expect(rows.map(\.detail) == [
            "Bench, incline, row, pulldown, laterals",
            "Squat, RDL, leg press, calves",
            "Weighted pull-up, OHP, row, curls",
            "Deadlift, front squat, leg curl"
        ])
    }

    @Test(
        "Step 3 lists every day of the split the days give, named with a middle dot",
        arguments: DaysPerWeek.allCases
    )
    func step3_listsEveryDayOfTheSplit(_ days: DaysPerWeek) {
        let preview = ProgramTemplates.preview(days: days)
        let rows = Self.days(days)
        #expect(rows.count == days.rawValue)
        #expect(rows.map(\.detail) == preview.days.map(\.line))
        #expect(rows.map(\.title) == preview.days.map { $0.name.replacingOccurrences(of: " — ", with: " · ") })
        #expect(rows.allSatisfy { !$0.title.contains("—") })
        #expect(rows.map(\.id) == Array(rows.indices))
    }

    @Test("Step 3's sentence names the program, its eight weeks and the stored unit", arguments: [
        (DaysPerWeek.three, Units.lb, "Full Body, 8 weeks, pounds. Editable any time."),
        (.four, .kg, "Upper / Lower, 8 weeks, kilograms. Editable any time."),
        (.five, .lb, "Push / Pull / Legs, 8 weeks, pounds. Editable any time."),
        (.six, .kg, "Body-Part Split, 8 weeks, kilograms. Editable any time.")
    ])
    func step3_sentence_namesProgramWeeksAndUnit(days: DaysPerWeek, units: Units, sentence: String) {
        #expect(Self.model(OnboardingState(step: .program, days: days, units: units)).body == sentence)
    }

    @Test("The goal changes nothing step 3 shows", arguments: TrainingGoal.allCases)
    func step3_isTheSameForEveryGoal(_ goal: TrainingGoal) {
        let state = OnboardingState(step: .program, goal: goal)
        #expect(Self.model(state) == Self.model(OnboardingState(step: .program)))
    }
}
