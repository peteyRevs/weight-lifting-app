import XCTest

/// One stop of VoiceOver on a step, as the app's accessibility tree gives it to a real client.
struct AdversarialStop: Equatable, CustomStringConvertible {
    let label: String
    var isButton = false
    var isSelected = false
    var isEnabled = true

    var description: String {
        "\(isButton ? "button" : "text") \"\(label)\"\(isSelected ? " selected" : "")\(isEnabled ? "" : " not enabled")"
    }
}

/// The tables of the notes' "The intended VoiceOver trees" (F08 S2), typed here from the brief's copy.
extension OnboardingAdversarial {
    static let pinned = [AdversarialStop(label: "Skip setup", isButton: true)]
    static let stepOne = [
        AdversarialStop(label: "Step 1 of 3"),
        AdversarialStop(label: "What are you training for?"),
        AdversarialStop(label: "This sets how your loads progress week to week."),
        AdversarialStop(label: "Get stronger, Low reps, linear load increases", isButton: true),
        AdversarialStop(label: "Build muscle, Moderate reps, volume tracking", isButton: true),
        AdversarialStop(label: "Both, honestly, Barbell strength + accessory volume", isButton: true, isSelected: true),
        AdversarialStop(label: "Stay consistent, Habit first, numbers second", isButton: true),
        AdversarialStop(label: "Continue", isButton: true)
    ] + pinned
    static let stepTwo = [
        AdversarialStop(label: "Back", isButton: true),
        AdversarialStop(label: "Step 2 of 3"),
        AdversarialStop(label: "How many days a week?"),
        AdversarialStop(label: "Pick the number you will actually hit, not the one you want to hit."),
        AdversarialStop(label: "3 days, Full body each session", isButton: true),
        AdversarialStop(label: "4 days, Upper / lower split", isButton: true, isSelected: true),
        AdversarialStop(label: "5 days, Push, pull, legs + accessories", isButton: true),
        AdversarialStop(label: "6 days, Body-part split", isButton: true),
        AdversarialStop(label: "Continue", isButton: true)
    ] + pinned
    static let stepThree = [
        AdversarialStop(label: "Back", isButton: true),
        AdversarialStop(label: "Step 3 of 3"),
        AdversarialStop(label: "Your program"),
        AdversarialStop(label: "Upper / Lower, 8 weeks, pounds. Editable any time."),
        AdversarialStop(label: "Upper A · Push focus, Bench, incline, row, pulldown, laterals"),
        AdversarialStop(label: "Lower A · Squat focus, Squat, RDL, leg press, calves"),
        AdversarialStop(label: "Upper B · Pull focus, Weighted pull-up, OHP, row, curls"),
        AdversarialStop(label: "Lower B · Hinge focus, Deadlift, front squat, leg curl"),
        AdversarialStop(label: "Start training", isButton: true)
    ] + pinned
    static let fullBodyRows = [
        "Full Body A · Squat focus, Squat, bench, pulldown, laterals, curl",
        "Full Body B · Bench focus, Bench, RDL, row, leg press, pushdown",
        "Full Body C · Deadlift focus, Deadlift, OHP, pull-up, leg curl, rear delt"
    ]
}
