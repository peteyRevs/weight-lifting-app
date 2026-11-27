import Foundation
import LedgerDomain

/// What the session list draws (spec §4.3 "Watch — session list", §5.1 `exList`).
nonisolated struct WatchListModel: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        /// The row's exercise, in `WorkoutState.exercises`: what a tap selects.
        let exerciseIndex: Int
        /// "1", counted from 1 in workout order; orange when the row is current.
        let number: String
        /// The exercise's name, "A · Lat Pulldown" in a superset.
        let name: String
        /// "5 × 5 @ 185".
        let scheme: String
        /// Every set of it is logged: the name dims and a "✓" shows.
        let isDone: Bool
        /// The exercise the set screen shows: the orange fill and border.
        let isCurrent: Bool
    }

    /// "2 OF 5 DONE".
    let header: String
    let rows: [Row]
    /// "End workout", which opens the end overlay.
    let endWorkout: String
}

/// What the end overlay draws (spec §4.3 "Watch — end workout"): the title, the line, and which of "Save workout"
/// and "Discard" it offers, beside "Keep lifting", which it always does.
nonisolated struct WatchEndModel: Equatable, Sendable {
    /// "End workout?".
    let title: String
    /// "18 of 20 sets logged · 24,180 lb moved".
    let line: String
    /// The same facts as VoiceOver reads them: "18 of 20 sets logged, 24,180 lb moved".
    let spokenLine: String
    let save: String
    let discard: String
    let keepLifting: String
    /// The sets logged so far (`WorkoutState.doneSets`).
    let loggedSetCount: Int
    /// Whether "Save workout" can end the workout: once a set is logged, as on the phone's sheet. The overlay draws
    /// it only then: a grey pill on the wrist is a target that does nothing.
    let canSave: Bool

    /// Whether the overlay offers "Discard" (`offersDiscard(loggedSetCount:)`).
    var offersDiscard: Bool {
        Self.offersDiscard(loggedSetCount: loggedSetCount)
    }

    /// Whether the watch may discard a workout with `loggedSetCount` sets logged: only while none is, so that the
    /// watch never throws logged sets away (orchestrator ruling 7, F18 S6b). The overlay offers "Discard" by it, and
    /// the store's pump asks it again of the newest workout when the discard's turn comes, so a set logged elsewhere
    /// after the overlay was drawn still refuses it. **Pending Pete:** whether a workout with logged sets may be
    /// discarded from the watch, perhaps behind a second confirm, is the product owner's to rule on; this is the one
    /// place that rule lives. With it, "Save workout" and "Discard" are never offered together.
    static func offersDiscard(loggedSetCount: Int) -> Bool {
        loggedSetCount == 0
    }
}

nonisolated extension WatchPresentation {
    /// The session list of `state`: one row per exercise, in workout order. The scheme is the phone's "Remaining"
    /// row's (FeatureWorkout): the sets without the drop set, the first set's reps, and here its weight too, in the
    /// workout's unit, as spec §5.1 reads them off the first set. The current row is the set screen's exercise
    /// (`activeRow(of:)`); the header counts the exercises with every set logged.
    static func list(_ state: WorkoutState, locale: Locale) -> WatchListModel {
        let current = activeRow(of: state)?.exercise
        let digits = IntegerFormatStyle<Int>(locale: locale)
        let rows = state.exercises.enumerated().map { index, exercise in
            let first = exercise.sets.first
            let name = letter(of: index, in: state.exercises).map { $0 + separator + exercise.name } ?? exercise.name
            return WatchListModel.Row(
                exerciseIndex: index,
                number: digits.format(index + 1),
                name: name,
                scheme: WatchWorkoutCopy.scheme(
                    sets: exercise.sets.count { $0.kind != .drop },
                    reps: first?.reps.value ?? exercise.targetReps,
                    load: (first?.weight ?? exercise.targetLoad).formatted(in: state.units),
                    locale: locale
                ),
                isDone: !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isDone),
                isCurrent: index == current
            )
        }
        return WatchListModel(
            header: WatchWorkoutCopy.exercisesDone(
                digits.format(rows.count(where: \.isDone)), of: digits.format(rows.count), locale: locale
            ),
            rows: rows,
            endWorkout: WatchWorkoutCopy.endWorkoutButton
        )
    }

    /// The end overlay of `state`: the phone's "End workout?" sheet (`WorkoutPresentation.finishSheet`,
    /// FeatureWorkout). The numbers are the Domain's; the line is two facts, each a text of its own, joined here
    /// (standards §7). The total picks the plural form; the done count is passed as text, in the lifter's digits.
    static func end(_ state: WorkoutState, locale: Locale) -> WatchEndModel {
        let facts = [
            WatchWorkoutCopy.setsLogged(
                done: IntegerFormatStyle<Int>(locale: locale).format(state.doneSets),
                of: state.totalSets,
                locale: locale
            ),
            WatchWorkoutCopy.moved(state.volume.formatted(in: state.units), units: state.units, locale: locale)
        ]
        return WatchEndModel(
            title: WatchWorkoutCopy.endWorkout,
            line: facts.joined(separator: separator),
            spokenLine: facts.joined(separator: ", "),
            save: WatchWorkoutCopy.saveWorkout,
            discard: WatchWorkoutCopy.discard,
            keepLifting: WatchWorkoutCopy.keepLifting,
            loggedSetCount: state.doneSets,
            canSave: state.doneSets > 0
        )
    }
}
