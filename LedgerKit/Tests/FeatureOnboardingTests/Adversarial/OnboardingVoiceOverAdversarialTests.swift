#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F08 S2 adversarial round 1, criteria 2, 3 and 8: what a hosted screen hands VoiceOver in each step and state.
    /// The expected reading is written from the brief: the screen's parts top to bottom ("Back", the bars as one
    /// element "Step n of 3", the title, its line, the picks as one button each "{label}, {sub}" or the days as
    /// text, the failure line, the primary button, "Skip setup").
    @Suite("Adversarial F08 S2 · what VoiceOver gets")
    struct OnboardingVoiceOverAdversarialTests {
        typealias Element = AccessibilityElementSnapshot

        /// A state of the screen and a name for it in a failure.
        nonisolated struct Shown: Sendable, CustomStringConvertible {
            let description: String
            let state: OnboardingState

            static let all: [Shown] = [
                Shown(description: "step 1", state: OnboardingState()),
                Shown(description: "step 1, Get stronger", state: OnboardingState(goal: .strength)),
                Shown(description: "step 2", state: OnboardingState(step: .days)),
                Shown(description: "step 2, 6 days", state: OnboardingState(step: .days, days: .six)),
                Shown(description: "step 3, four days", state: OnboardingState(step: .program)),
                Shown(description: "step 3, three days", state: OnboardingState(step: .program, days: .three)),
                Shown(description: "step 3, five days", state: OnboardingState(step: .program, days: .five)),
                Shown(
                    description: "step 3, six days, kg",
                    state: OnboardingState(step: .program, days: .six, units: .kg)
                ),
                Shown(description: "step 3, failed", state: OnboardingState(step: .program, phase: .failed)),
                Shown(description: "step 1, failed", state: OnboardingState(phase: .failed)),
                Shown(description: "step 3, saving", state: OnboardingState(step: .program, phase: .saving)),
                Shown(description: "step 2, saving", state: OnboardingState(step: .days, phase: .saving))
            ]
        }

        static func screen(
            _ state: OnboardingState,
            send: @escaping (OnboardingAction) -> Void = { _ in }
        ) -> OnboardingScreen {
            OnboardingScreen(model: OnboardingPresentation.make(state, locale: Fixtures.locale), send: send)
        }

        static func said(_ element: Element) -> String {
            [element.label, element.value].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        /// The picks of a step as VoiceOver reads them, with the one that is picked.
        static func picks(_ state: OnboardingState) -> [(said: String, isPicked: Bool)] {
            switch state.step {
            case .goal: BriefCopy.goals.map { ("\($0.title), \($0.detail)", $0.goal == state.goal) }
            case .days: BriefCopy.days.map { ("\($0.title), \($0.detail)", $0.days == state.days) }
            case .program: []
            }
        }

        static func primary(_ state: OnboardingState) -> String {
            if state.phase == .failed {
                return BriefCopy.retry
            }
            return state.step == .program ? BriefCopy.startTraining : BriefCopy.continueTitle
        }

        /// The whole reading of a state, top to bottom.
        static func reading(_ state: OnboardingState) -> [String] {
            var reading = state.step == .goal ? [] : [BriefCopy.back]
            reading.append(BriefCopy.step(state.step.rawValue + 1))
            switch state.step {
            case .goal: reading += [BriefCopy.goalTitle, BriefCopy.goalBody]
            case .days: reading += [BriefCopy.daysTitle, BriefCopy.daysBody]
            case .program: reading += [BriefCopy.programTitle, BriefCopy.programBody(state.days, state.units)]
            }
            reading += picks(state).map(\.said)
            if state.step == .program {
                reading += BriefCopy.dayRows(state.days).map { "\($0.title), \($0.detail)" }
            }
            reading += state.phase == .failed ? [BriefCopy.saveFailed] : []
            return reading + [primary(state), BriefCopy.skipSetup]
        }

        @Test(
            "Each step and state reads top to bottom as the brief lays it out, and nothing else is read",
            arguments: Shown.all
        )
        func tree_everyState_readsAsTheBrief(_ shown: Shown) {
            for appearance in [SnapshotAppearance(.light, .large), SnapshotAppearance(.dark, .accessibility3)] {
                let elements = Self.screen(shown.state).accessibilityElements(appearance)
                let said = elements.map(Self.said)
                // A day of step 3 may be one element or two; joined, the reading is the same.
                #expect(
                    said.joined(separator: ", ") == Self.reading(shown.state).joined(separator: ", "),
                    "\(appearance)"
                )
                #expect(said.allSatisfy { !$0.isEmpty }, "an element with nothing to say. \(appearance): \(elements)")
                let tops = elements.map(\.frame.minY)
                #expect(tops == tops.sorted(), "VoiceOver's order is the order on screen. \(appearance): \(elements)")
                #expect(elements.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 }, "\(elements)")
            }
        }

        @Test("The bars are one element, Step n of 3, and no button", arguments: Shown.all)
        func progress_everyState_isOneElement(_ shown: Shown) {
            let elements = Self.screen(shown.state).accessibilityElements()
            let step = BriefCopy.step(shown.state.step.rawValue + 1)
            let bars = elements.filter { Self.said($0).contains("Step") }
            #expect(bars.map(Self.said) == [step])
            #expect(bars.allSatisfy { !$0.traits.contains(.button) && !$0.traits.contains(.selected) })
        }

        @Test(
            "Each pick is one button labelled label, sub with no value, selected only when it is the pick",
            arguments: Shown.all
        )
        func picks_everyState_areButtonsWithOneSelected(_ shown: Shown) {
            let elements = Self.screen(shown.state).accessibilityElements()
            for pick in Self.picks(shown.state) {
                let matches = elements.filter { $0.label == pick.said }
                #expect(matches.count == 1, "\(pick.said): \(elements)")
                let haveNoValue = matches.allSatisfy(\.value.isEmpty)
                #expect(haveNoValue, "criterion 8: no value. \(matches)")
                #expect(matches.allSatisfy { $0.traits.contains(.button) }, "\(matches)")
                #expect(matches.allSatisfy { $0.traits.contains(.selected) == pick.isPicked }, "\(matches)")
            }
            let selected = elements.filter { $0.traits.contains(.selected) }
            #expect(selected.count == (shown.state.step == .program ? 0 : 1), "\(selected)")
        }

        @Test(
            "Step 3's days are text: no button, no tick, and activating one sends nothing",
            arguments: DaysPerWeek.allCases
        )
        func stepThree_days_areReadNotTapped(days: DaysPerWeek) {
            var sent: [OnboardingAction] = []
            let state = OnboardingState(step: .program, days: days)
            let controls = [BriefCopy.back, BriefCopy.startTraining, BriefCopy.skipSetup]
            let buttons = Self.screen(state) { sent.append($0) }.withAccessibilityElements { elements in
                let rows = elements.filter { !controls.contains($0.accessibilityLabel ?? "") }
                for row in rows {
                    _ = row.accessibilityActivate()
                }
                return elements.filter { $0.accessibilityTraits.contains(.button) }.map { $0.accessibilityLabel ?? "" }
            }
            #expect(sent.isEmpty, "a day row sent \(sent)")
            #expect(buttons == controls, "the only buttons of step 3")
        }
    }

    /// What the controls do when VoiceOver activates them, their size, and the root.
    extension OnboardingVoiceOverAdversarialTests {
        @Test("Every control sends its action once when VoiceOver activates it; a picked option can be picked again")
        func controls_activated_sendTheirAction() {
            let expected: [(Shown, [OnboardingAction])] = [
                (Shown.all[0], BriefCopy.goals.map { .pickGoal($0.goal) } + [.advance, .skipSetup]),
                (Shown.all[2], [.back] + BriefCopy.days.map { .pickDays($0.days) } + [.advance, .skipSetup]),
                (Shown.all[4], [.back, .startTraining, .skipSetup]),
                (Shown.all[8], [.retry, .skipSetup])
            ]
            for (shown, actions) in expected {
                var sent: [OnboardingAction] = []
                Self.screen(shown.state) { sent.append($0) }.withAccessibilityElements { elements in
                    let enabled = elements.filter {
                        $0.accessibilityTraits.contains(.button) && !$0.accessibilityTraits.contains(.notEnabled)
                    }
                    for element in enabled {
                        _ = element.accessibilityActivate()
                    }
                }
                // After a failure the brief names Retry and Skip setup; whether Back answers there is a question
                // for the product, so only those two are required of that state.
                let relevant = shown.state.phase == .failed ? sent.filter { $0 != .back } : sent
                #expect(relevant == actions, "\(shown)")
            }
        }

        @Test("During a save and after it no control answers, and VoiceOver hears them as dimmed", arguments: [
            OnboardingState.Phase.saving, .retrying, .saved
        ])
        func controls_whileSavingAndAfter_doNotAnswer(phase: OnboardingState.Phase) {
            for step in OnboardingState.Step.allCases {
                var sent: [OnboardingAction] = []
                let state = OnboardingState(step: step, phase: phase)
                let traits = Self.screen(state) { sent.append($0) }.withAccessibilityElements { elements in
                    let buttons = elements.filter { $0.accessibilityTraits.contains(.button) }
                    for button in buttons {
                        _ = button.accessibilityActivate()
                    }
                    return buttons.map { ($0.accessibilityLabel ?? "", $0.accessibilityTraits.contains(.notEnabled)) }
                }
                #expect(sent.isEmpty, "\(step) \(phase): \(sent)")
                let enabled = traits.filter { !$0.1 }.map(\.0)
                #expect(enabled.isEmpty, "\(step) \(phase): still enabled \(enabled)")
                #expect(!traits.isEmpty)
            }
        }

        @Test("Every control is at least 44 pt each way at every text size of the matrix", arguments: Shown.all)
        func hitTargets_everyState_areAtLeast44(_ shown: Shown) {
            for appearance in SnapshotAppearance.phoneMatrix {
                let buttons = Self.screen(shown.state).accessibilityElements(appearance)
                    .filter { $0.traits.contains(.button) }
                let small = buttons.filter { $0.frame.width < 44 || $0.frame.height < 44 }
                #expect(small.isEmpty, "\(appearance): \(small)")
                #expect(buttons.count >= 2)
            }
        }

        @Test("The root reads as its screen does, and taps on it reach its store: picks, steps, one attempt")
        func root_hosted_readsAndAnswersAsItsScreen() throws {
            let scene = try AdversarialScene(.seeded())
            let root = OnboardingRoot(store: scene.store, prepareRetry: {})
            func parts(_ elements: [Element]) -> [String] {
                elements.map { "\($0.label) | \($0.value) | \($0.traits.rawValue)" }
            }
            #expect(parts(root.accessibilityElements()) ==
                parts(Self.screen(OnboardingState()).accessibilityElements()))
            root.withLiveAccessibilityElements { read in
                @MainActor
                func tap(_ label: String) {
                    _ = read().first { $0.accessibilityLabel == label }?.accessibilityActivate()
                }
                tap("Get stronger, Low reps, linear load increases")
                tap(BriefCopy.continueTitle)
                tap("6 days, Body-part split")
                tap(BriefCopy.back)
                #expect(scene.store.state == OnboardingState(step: .goal, goal: .strength, days: .six))
                tap(BriefCopy.continueTitle)
                tap(BriefCopy.continueTitle)
                let said = read().map { $0.accessibilityLabel ?? "" }
                #expect(said.contains("Body-Part Split, 8 weeks, pounds. Editable any time."), "\(said)")
                tap(BriefCopy.startTraining)
                let attempt = scene.store.attempt
                tap(BriefCopy.startTraining)
                tap(BriefCopy.skipSetup)
                tap(BriefCopy.back)
                #expect(scene.store.attempt == attempt)
                #expect(attempt?.goal == .strength)
                #expect(attempt?.days == .six)
                #expect(scene.store.state.step == .program)
            }
        }
    }
#endif
