import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the sheet that creates the lifter's own exercise, or edits one (F12 S3; the M1 store convention, as
/// `OnboardingStore` saves).
///
/// **Intents are synchronous and decide nothing.** A field's tap changes the draft and forgets the problem Save last
/// found, so a line under a field never speaks of a name since retyped. Choosing a primary muscle takes it out of
/// the secondary ones (N15).
///
/// **Saving (N16).** "Save" is accepted while the lifter is editing; it makes the next `attempt`, which is the id of
/// the sheet's task, and nothing answers until the save has run. `save()` reads the live exercises, builds the
/// exercise from the draft (`CustomExerciseDraft`) and stores it with one `ExerciseRepository.save`; a second call
/// while one runs does nothing. A rule the draft breaks is shown under its field, a save that fails over Save, and
/// either way the sheet stays up with the lifter's draft. A save cancelled before its write, because the sheet went
/// down, writes nothing and shows nothing. Once the repository has saved, the phase is `.saved` and the sheet
/// closes.
///
/// **Editing** (Pete's question 5, A) stores the exercise again under its id, with every field as the sheet holds
/// it. Only the lifter's own exercises are edited: a catalog exercise is never saved from here (the history offers
/// no "Edit" for one).
@MainActor @Observable
final class CreateExerciseStore {
    enum Phase: Equatable {
        case editing, saving, saved
    }

    /// The exercise being edited; nil for a new one.
    let original: Exercise?
    private(set) var draft: CustomExerciseDraft
    private(set) var phase = Phase.editing
    private(set) var problem: CreateExerciseProblem?
    /// The save the sheet's `.task(id:)` runs; nil until the first accepted "Save".
    private(set) var attempt: Int?
    @ObservationIgnored private var isSaveRunning = false

    @ObservationIgnored @Dependency(\.exerciseRepository) private var exercises
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    private var logger: LedgerLogger {
        injectedLogger.category("library")
    }

    /// A store for a new exercise, or for the edit of `exercise`. Making one reads and writes nothing.
    init(editing exercise: Exercise? = nil) {
        original = exercise
        draft = exercise.map(CustomExerciseDraft.init) ?? CustomExerciseDraft()
    }

    /// What the sheet draws.
    var model: CreateExerciseModel {
        CreateExercisePresentation.make(CreateExerciseInput(
            draft: draft,
            isEdit: original != nil,
            isSaving: phase == .saving,
            problem: problem,
            locale: locale
        ))
    }

    // MARK: Intents

    func send(_ action: CreateExerciseAction) {
        guard phase == .editing else {
            return
        }
        switch action {
        case let .setName(name):
            draft.name = name
        case let .setEquipment(equipment):
            draft.equipment = equipment
        case let .setPrimaryMuscle(muscle):
            draft.primaryMuscle = muscle
            draft.secondaryMuscles.remove(muscle)
        case let .setSecondaryMuscle(muscle, isOn):
            if isOn, muscle != draft.primaryMuscle {
                draft.secondaryMuscles.insert(muscle)
            } else {
                draft.secondaryMuscles.remove(muscle)
            }
        case let .setPattern(pattern):
            draft.pattern = pattern
        case .save:
            phase = .saving
            attempt = (attempt ?? 0) + 1
            return
        }
        problem = nil
    }

    // MARK: Work the sheet's task runs

    /// Runs the accepted save, once: builds the exercise from the draft against the live exercises and stores it.
    func save() async {
        guard phase == .saving, !isSaveRunning else {
            return
        }
        isSaveRunning = true
        defer { isSaveRunning = false }
        do {
            guard original?.isCustom != false else {
                throw CreateExerciseStoreError.catalogExercise
            }
            let live = try await exercises.all()
            try Task.checkCancellation()
            let exercise = try build(among: live)
            try await exercises.save(exercise)
            phase = .saved
        } catch let invalid as CustomExerciseError {
            phase = .editing
            problem = .invalid(invalid)
        } catch {
            let isCancellation = error is CancellationError && Task.isCancelled
            if !isCancellation {
                logger.log.error("An exercise could not be saved: \(String(describing: error), privacy: .public)")
            }
            phase = .editing
            problem = isCancellation ? nil : .failed
        }
    }

    /// The exercise the draft makes, under the edited exercise's id or a new one.
    private func build(among live: [Exercise]) throws(CustomExerciseError) -> Exercise {
        try draft.exercise(id: original?.id ?? ExerciseID(uuid()), among: live)
    }
}

/// Why `CreateExerciseStore` refused a save the repository was never asked for.
nonisolated enum CreateExerciseStoreError: Error {
    /// The sheet was handed a catalog exercise to edit, which only the catalog's upgrades change.
    case catalogExercise
}
