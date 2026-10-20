import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the exercise library sheet (F11 S14, criterion 19): the search field's text, the two chips,
/// the picks, and whether the sheet is up. The Day editor's store owns it and lives as long as the Day
/// editor, so the chips chosen are still chosen when the sheet opens again (the plan's behaviour 14).
///
/// **Every action is applied synchronously**, as `ExercisePickerAction` says, `.setQuery` included: the
/// search field reads the model's query back, so typing would lag behind a store that waited. Nothing is
/// debounced: the presentation filters the whole list on every keystroke (within the 10 ms budget).
///
/// **"Add"** builds the slots at the tap, each with its id from `\.uuid`, and queues them on the Day
/// editor's session as one edit, so the slots shown are the ones written. An exercise that is no longer
/// stored is left out; one `DayEditing.newSlot` refuses (a start load below zero) is left out and logged.
/// "Add" and "Cancel" both empty the query and the picks, keep the chips and close the sheet.
@MainActor @Observable
final class ExercisePickerStore {
    private(set) var query = ""
    private(set) var muscle: ExerciseSearch.MuscleFilter?
    private(set) var equipment: Equipment?
    private(set) var picks: [ExerciseID] = []
    /// Whether the sheet is up: set by the Day editor's "+ Add exercise from library".
    var isShown = false

    @ObservationIgnored private let day: DayTemplateID
    @ObservationIgnored private let session: ProgramEditSession<DayEditorEdit>

    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    private var logger: LedgerLogger {
        injectedLogger.category("program")
    }

    init(day: DayTemplateID, session: ProgramEditSession<DayEditorEdit>) {
        self.day = day
        self.session = session
    }

    /// The sheet's model over `exercises`, with the day's exercises as the Day editor shows them, its
    /// waiting edits included.
    func model(exercises: [Exercise]) -> ExercisePickerModel {
        let slots = session.shown?.days.first { $0.id == day }?.slots ?? []
        return ExercisePickerPresentation.make(ExercisePickerInput(
            exercises: exercises,
            dayExercises: Set(slots.map(\.exerciseID)),
            query: query,
            muscle: muscle,
            equipment: equipment,
            picks: picks,
            locale: locale
        ))
    }

    /// Applies `action`; "Add" builds its slots from `exercises` and `settings`.
    func send(_ action: ExercisePickerAction, exercises: [ExerciseID: Exercise], settings: Settings) {
        switch action {
        case let .setQuery(text):
            query = text
        case let .setMuscle(filter):
            muscle = filter
        case let .setEquipment(kind):
            equipment = kind
        case let .setPicked(isPicked, exercise):
            if !isPicked {
                picks.removeAll { $0 == exercise }
            } else if !picks.contains(exercise) {
                picks.append(exercise)
            }
        case .clearFilters:
            query = ""
            muscle = nil
            equipment = nil
        case let .add(ids):
            add(ids, exercises: exercises, settings: settings)
            close()
        case .cancel:
            close()
        }
    }

    private func add(_ ids: [ExerciseID], exercises: [ExerciseID: Exercise], settings: Settings) {
        let slots = ids.compactMap { id -> Slot? in
            guard let exercise = exercises[id] else {
                return nil
            }
            do {
                return try DayEditing.newSlot(
                    id: SlotID(uuid()),
                    exercise: exercise,
                    units: settings.units,
                    defaultRest: settings.defaultRest
                )
            } catch {
                logger.log.error("An exercise was not added to a day: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        session.enqueue(.slot(.add(slots), day: day))
    }

    private func close() {
        query = ""
        picks = []
        isShown = false
    }
}
