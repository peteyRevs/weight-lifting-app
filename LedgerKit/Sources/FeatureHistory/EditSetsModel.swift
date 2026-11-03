import LedgerDomain

/// What the edit sheet asks the store to do: every control's tap, carried in the model.
nonisolated enum EditSetsAction: Equatable, Sendable {
    case step(SetID, SetEditing.Field, StepDirection)
    case save
}

/// What opens the edit sheet: the workout as the detail last read it, and the units the detail draws it in.
nonisolated struct EditSetsRequest: Identifiable, Equatable, Sendable {
    let workout: WorkoutState
    let units: Units

    var id: WorkoutID {
        workout.id
    }
}

/// Everything the edit sheet draws and speaks, as `EditSetsPresentation.make(_:)` builds it. Every string is final and
/// every control carries what its tap means: the views draw the model and decide nothing.
nonisolated struct EditSetsModel: Equatable, Sendable {
    let title: String
    let cancel: String
    let exercises: [Exercise]
    let foot: Foot
    /// False while a save runs: nothing on the sheet answers, and no swipe takes it down.
    let isEnabled: Bool
    /// Up once a save found the workout deleted: the alert that says so, then the sheet and the detail close.
    let workoutGone: WorkoutGone?

    /// One exercise of the workout, a heading over its logged sets, or over "Nothing logged" when it has none.
    struct Exercise: Identifiable, Equatable, Sendable {
        let id: WorkoutExerciseID
        let name: String
        let nothingLogged: String?
        let sets: [SetRow]
    }

    /// One logged set: its weight's stepper over its reps'.
    struct SetRow: Identifiable, Equatable, Sendable {
        let id: SetID
        let weight: Field
        let reps: Field
    }

    /// One stepper: "Set 2 weight", "185 lb", read "185 pounds"; a side with no action is switched off.
    struct Field: Equatable, Sendable {
        let label: String
        let value: String
        let spokenValue: String
        let decrement: EditSetsAction?
        let increment: EditSetsAction?
    }

    /// The pinned foot: the failure's line when a save failed, then "Save", which has no action until something
    /// changed.
    struct Foot: Equatable, Sendable {
        let problem: String?
        let save: String
        let action: EditSetsAction?
    }

    struct WorkoutGone: Equatable, Sendable {
        let title: String
        let message: String
        let okay: String
    }
}
