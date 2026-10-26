import Foundation

/// A custom exercise as the lifter fills it in (F12 S3; spec §3.10, decision #12): its name, equipment, primary and
/// secondary muscles and movement pattern, and the one rule that turns it into an `Exercise` (N15).
///
/// **The name** is stored as it draws (`+Name`): trimmed of blanks and of characters that draw nothing, every kind
/// of space one plain space, no run of spaces. It must then show something, be 2–40 characters (as the lifter counts
/// them: `Character`s) and at most 160 scalars, hold no control character, line separator or direction override,
/// and differ from every other live exercise's name by `ExerciseSearch.key`, the key the Library searches and sorts
/// by. So a name that draws as another's is that name (F12 S3, findings S3-1 to S3-4).
///
/// **What the form does not ask** (Pete's question 4, A/A): the short name is the name; the start load is 0 in both
/// units, so a first slot starts empty and the lifter sets it; no curated alternatives; and the step is the
/// equipment's default (`Equipment.defaultStep(in:)`), which an `Exercise` does not store.
///
/// **Editing** (Pete's question 5, A) starts from the stored exercise and builds it again under its own id, so every
/// field can change; workouts keep the name they were logged under, and programs follow the id.
public struct CustomExerciseDraft: Hashable, Sendable {
    /// N15: how many characters a trimmed name may have.
    public static let nameLength = 2 ... 40

    /// The name as typed, untrimmed.
    public var name: String
    public var equipment: Equipment
    public var primaryMuscle: MuscleGroup
    /// Never stored with the primary muscle among them: `exercise(id:among:)` refuses that.
    public var secondaryMuscles: Set<MuscleGroup>
    public var pattern: MovementPattern

    /// A new draft: no name, and each choice the first of its kind.
    public init(
        name: String = "",
        equipment: Equipment = .barbell,
        primaryMuscle: MuscleGroup = .chest,
        secondaryMuscles: Set<MuscleGroup> = [],
        pattern: MovementPattern = .horizontalPush
    ) {
        self.name = name
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.pattern = pattern
    }

    /// The draft of a stored exercise, for its edit. Its primary muscle is never among the draft's secondary ones,
    /// even when the stored row holds it there (a sync, an import or a later version may write one; finding S3-5):
    /// the sheet offers no chip to clear it, so the draft takes it out, as choosing a primary muscle does.
    public init(_ exercise: Exercise) {
        self.init(
            name: exercise.name,
            equipment: exercise.equipment,
            primaryMuscle: exercise.primaryMuscle,
            secondaryMuscles: Set(exercise.secondaryMuscles).subtracting([exercise.primaryMuscle]),
            pattern: exercise.pattern
        )
    }

    /// The lifter's exercise `id`, built from the draft, or the first rule it breaks. `live` is every live
    /// exercise; the one with `id` is left out of the name's comparison, so an edit may keep its own name.
    public func exercise(id: ExerciseID, among live: [Exercise]) throws(CustomExerciseError) -> Exercise {
        guard !drawsNothing else {
            throw .blankName
        }
        let trimmed = storedName
        // Graphemes are what the lifter counts; the scalar cap bounds what one grapheme can carry (S3-4).
        guard Self.nameLength.contains(trimmed.count), trimmed.unicodeScalars.count <= Self.nameScalars else {
            throw .nameLength(trimmed.count)
        }
        guard !trimmed.unicodeScalars.contains(where: Self.isRefused) else {
            throw .controlCharacter
        }
        let key = ExerciseSearch.key(trimmed)
        if let other = live.first(where: { $0.id != id && ExerciseSearch.key($0.name) == key }) {
            throw .duplicateName(other.id)
        }
        guard !secondaryMuscles.contains(primaryMuscle) else {
            throw .primaryAmongSecondaries
        }
        return Exercise(
            id: id,
            name: trimmed,
            shortName: trimmed,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            // In the Domain's order of the groups, so one draft always stores one list.
            secondaryMuscles: MuscleGroup.allCases.filter(secondaryMuscles.contains),
            pattern: pattern,
            defaultStartLoad: [.lb: .zero, .kg: .zero],
            isCustom: true
        )
    }
}
