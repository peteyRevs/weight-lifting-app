import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the sheet that fixes a past workout's sets (F13 S3; the M1 store convention, as `CreateExerciseStore`).
///
/// **It edits a draft of the workout the detail last read** (`EditSetsRequest`), by the Domain's rule (`SetEditing`,
/// N11), and follows nothing while it is up. "Save" is off until the draft differs from what was read; a step that
/// comes back to the stored value turns it off again.
///
/// **A save runs once** (N12). "Save" is accepted while editing with something changed; it makes the next `attempt`,
/// the id of the sheet's task, and `save()` hands every changed exercise to `updateSets(_:of:)` in one call. Then:
/// stored, the sheet closes; a failure is logged and said in a line, and the sheet stays; a workout deleted meanwhile
/// (`missingRow`) is said in an alert, whose "OK" closes the sheet and the detail; a run cancelled with the view stores
/// nothing or all of it (one transaction), says nothing, and leaves the draft to save again.
@MainActor @Observable
final class EditSetsStore {
    enum Phase: Equatable {
        case editing, saving, saved, workoutGone
    }

    private(set) var phase = Phase.editing
    /// The save the sheet's `.task(id:)` runs; nil until "Save" is first accepted.
    private(set) var attempt: Int?
    private(set) var draft: WorkoutState
    private(set) var saveFailed = false

    @ObservationIgnored private let original: WorkoutState
    @ObservationIgnored private let units: Units
    @ObservationIgnored private var isSaveRunning = false

    @ObservationIgnored @Dependency(\.workoutRepository) private var workouts
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    private var logger: LedgerLogger {
        injectedLogger.category("history")
    }

    init(_ request: EditSetsRequest) {
        original = request.workout
        draft = request.workout
        units = request.units
    }

    var model: EditSetsModel {
        EditSetsPresentation.make(EditSetsInput(
            draft: draft,
            units: units,
            locale: locale,
            hasChanges: !changes.isEmpty,
            isSaving: phase == .saving,
            saveFailed: saveFailed,
            workoutGone: phase == .workoutGone
        ))
    }

    /// "Cancel" and VoiceOver's escape are refused while a save runs.
    var canClose: Bool {
        phase != .saving
    }

    private var changes: [WorkoutExerciseID: [LoggedSet]] {
        SetEditing.changes(from: original, to: draft)
    }

    // MARK: Intents

    func send(_ action: EditSetsAction) {
        guard phase == .editing else {
            return
        }
        switch action {
        case let .step(id, field, direction):
            draft = SetEditing.stepping(id, field, direction, in: draft, units: units)
            saveFailed = false
        case .save:
            guard !changes.isEmpty else {
                return
            }
            phase = .saving
            saveFailed = false
            attempt = (attempt ?? 0) + 1
        }
    }

    // MARK: Work the sheet's task runs

    /// Runs the accepted save, once.
    func save() async {
        guard phase == .saving, !isSaveRunning else {
            return
        }
        isSaveRunning = true
        defer { isSaveRunning = false }
        do {
            try await workouts.updateSets(changes, of: original.id)
            phase = .saved
        } catch RepositoryError.missingRow {
            phase = .workoutGone
        } catch {
            let isCancellation = error is CancellationError && Task.isCancelled
            if !isCancellation {
                logger.log.error("A workout's sets could not be saved: \(String(describing: error), privacy: .public)")
            }
            phase = .editing
            saveFailed = !isCancellation
        }
    }
}
