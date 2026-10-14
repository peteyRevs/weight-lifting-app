import Foundation
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// The "End workout?" sheet of `state`. The numbers are the Domain's (`doneSets`, `totalSets`,
    /// `volume`); the line is two facts, each a text of its own, joined here (standards §7). The total
    /// picks the plural form; the done count is passed as text, in the lifter's digits.
    /// `canDiscard` is false once a save was asked for: "Discard" is then not offered (F10 S7a, fix round 1).
    static func finishSheet(
        _ state: WorkoutState,
        isSaving: Bool,
        canDiscard: Bool = true,
        locale: Locale
    ) -> WorkoutFinishModel {
        let facts = [
            WorkoutCopy.setsLogged(
                done: IntegerFormatStyle<Int>(locale: locale).format(state.doneSets),
                of: state.totalSets,
                locale: locale
            ),
            WorkoutCopy.moved(state.volume.formatted(in: state.units), units: state.units, locale: locale)
        ]
        return WorkoutFinishModel(
            title: WorkoutCopy.endWorkout,
            keepLifting: WorkoutCopy.keepLifting,
            summary: facts.joined(separator: " · "),
            spokenSummary: facts.joined(separator: ", "),
            save: WorkoutCopy.saveWorkout,
            discard: canDiscard ? WorkoutCopy.discard : nil,
            canSave: state.doneSets > 0 && !isSaving,
            isEnabled: !isSaving
        )
    }

    /// The save did not go through. The line claims only what is known in every case (an end the session
    /// stored and could not save, and an end it refused): the workout is still on the phone.
    static var saveFailedAlert: WorkoutSaveFailedModel {
        WorkoutSaveFailedModel(
            title: WorkoutCopy.couldNotSaveWorkout,
            message: WorkoutCopy.stillOnThisPhone,
            retry: WorkoutCopy.tryAgainButton,
            close: WorkoutCopy.close
        )
    }
}
