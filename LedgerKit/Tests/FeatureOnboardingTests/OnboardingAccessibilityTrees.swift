#if os(iOS)
    @testable import FeatureOnboarding
    import LedgerDomain
    import UIKit

    /// The intended VoiceOver tree of every state the screen can be in, as the implementation notes write them
    /// ("The intended VoiceOver trees"). `OnboardingAccessibilityTests` reads each from the screen and compares it
    /// exactly. Decorative parts (the rules, the check, the bars' segments) are no stop and appear in no table; on
    /// step 1 "Back" keeps its place without being drawn, and is no stop either.
    nonisolated enum OnboardingTrees {
        static let failure = Stop.text("Couldn't save your program. Try again.")
        static let goalBody = Stop.text("This sets how your loads progress week to week.")
        static let fourDays = [
            Stop.text("Upper A · Push focus, Bench, incline, row, pulldown, laterals"),
            .text("Lower A · Squat focus, Squat, RDL, leg press, calves"),
            .text("Upper B · Pull focus, Weighted pull-up, OHP, row, curls"),
            .text("Lower B · Hinge focus, Deadlift, front squat, leg curl")
        ]

        static let all: [OnboardingTree] = [
            OnboardingTree(name: "Step 1, Both picked", state: OnboardingState(), expected: [
                .progress("Step 1 of 3"),
                .heading("What are you training for?"),
                goalBody,
                .button("Get stronger, Low reps, linear load increases"),
                .button("Build muscle, Moderate reps, volume tracking"),
                .button("Both, honestly, Barbell strength + accessory volume", .selected),
                .button("Stay consistent, Habit first, numbers second"),
                .button("Continue"),
                .button("Skip setup")
            ]),
            OnboardingTree(name: "Step 2, 4 days picked", state: OnboardingState(step: .days), expected: [
                .button("Back"),
                .progress("Step 2 of 3"),
                .heading("How many days a week?"),
                .text("Pick the number you will actually hit, not the one you want to hit."),
                .button("3 days, Full body each session"),
                .button("4 days, Upper / lower split", .selected),
                .button("5 days, Push, pull, legs + accessories"),
                .button("6 days, Body-part split"),
                .button("Continue"),
                .button("Skip setup")
            ]),
            OnboardingTree(name: "Step 3, four days", state: OnboardingState(step: .program), expected: [
                .button("Back"),
                .progress("Step 3 of 3"),
                .heading("Your program"),
                .text("Upper / Lower, 8 weeks, pounds. Editable any time.")
            ] + fourDays + [
                .button("Start training"),
                .button("Skip setup")
            ]),
            OnboardingTree(
                name: "Step 3, six days in kilograms",
                state: OnboardingState(step: .program, days: .six, units: .kg),
                expected: [
                    .button("Back"),
                    .progress("Step 3 of 3"),
                    .heading("Your program"),
                    .text("Body-Part Split, 8 weeks, kilograms. Editable any time."),
                    .text("Chest, Bench, incline, dip, fly"),
                    .text("Back, Row, pull-up, pulldown, chest-supported row"),
                    .text("Legs · Quad focus, Squat, front squat, leg press, calves"),
                    .text("Shoulders, OHP, laterals, rear delt, extension"),
                    .text("Arms, Curl, pushdown, DB curl, extension"),
                    .text("Legs · Hinge focus, Deadlift, RDL, leg curl, calves"),
                    .button("Start training"),
                    .button("Skip setup")
                ]
            ),
            OnboardingTree(
                name: "Step 3, the save failed",
                state: OnboardingState(step: .program, phase: .failed),
                expected: [
                    .button("Back", .notEnabled),
                    .progress("Step 3 of 3"),
                    .heading("Your program"),
                    .text("Upper / Lower, 8 weeks, pounds. Editable any time.")
                ] + fourDays + [
                    failure,
                    .button("Retry"),
                    .button("Skip setup")
                ]
            ),
            OnboardingTree(name: "Step 1, Skip setup failed", state: OnboardingState(phase: .failed), expected: [
                .progress("Step 1 of 3"),
                .heading("What are you training for?"),
                goalBody,
                .button("Get stronger, Low reps, linear load increases", .notEnabled),
                .button("Build muscle, Moderate reps, volume tracking", .notEnabled),
                .button("Both, honestly, Barbell strength + accessory volume", [.selected, .notEnabled]),
                .button("Stay consistent, Habit first, numbers second", .notEnabled),
                failure,
                .button("Retry"),
                .button("Skip setup")
            ]),
            OnboardingTree(
                name: "Step 3, saving",
                state: OnboardingState(step: .program, phase: .saving),
                expected: [
                    .button("Back", .notEnabled),
                    .progress("Step 3 of 3"),
                    .heading("Your program"),
                    .text("Upper / Lower, 8 weeks, pounds. Editable any time.")
                ] + fourDays + [
                    .button("Start training", .notEnabled),
                    .button("Skip setup", .notEnabled)
                ]
            ),
            OnboardingTree(
                name: "Step 3, retrying",
                state: OnboardingState(step: .program, phase: .retrying),
                expected: [
                    .button("Back", .notEnabled),
                    .progress("Step 3 of 3"),
                    .heading("Your program"),
                    .text("Upper / Lower, 8 weeks, pounds. Editable any time.")
                ] + fourDays + [
                    .button("Retry", .notEnabled),
                    .button("Skip setup", .notEnabled)
                ]
            )
        ]
    }
#endif
