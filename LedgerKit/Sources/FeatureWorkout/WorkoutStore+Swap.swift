import Foundation
import LedgerDomain

/// The swap of `WorkoutStore` (F10 S8b): the card's "Swap exercise", the sheet's read of the alternatives,
/// "Use", "Cancel", and the bests of an exercise a swap brings in. In a file of its own for its length; the
/// members of the store it uses are the store's alone.
///
/// **One sheet, one read.** "Swap exercise" opens the sheet for the shown exercise and makes the next
/// `swapAttempt`; the root's `.task(id:)` runs `loadSwap()` for it, so the read ends with the view. A read
/// whose task started again for the same attempt reads again, and the first answer is the one shown; an
/// answer for an earlier attempt is dropped.
///
/// **"Use" goes through the tap queue** (`WorkoutEdit.swap`, `enqueue`): the sheet goes down at once, the
/// taps made before it are applied first, and the plan refuses a choice the workout has moved past.
extension WorkoutStore {
    /// The swap sheet of the workout on screen; nil before the first "Swap exercise".
    var swapSheet: SwapSheetModel? {
        guard let swap, case let .loaded(state) = workout else {
            return nil
        }
        return WorkoutPresentation.swapSheet(swap, in: state, locale: locale)
    }

    /// The sheet's three actions.
    func answerSwap(_ action: WorkoutAction) {
        switch action {
        case .openSwap:
            openSwap()
        case .cancelSwap:
            dismiss([.swap])
        case let .updateProgram(isOn):
            if dialog == .swap {
                swap?.alsoUpdateProgram = isOn
            }
        default:
            break
        }
    }

    /// Opens the sheet for the shown exercise, while none of its sets is logged (S8 ruling Q2) and nothing
    /// else is shown over the cover. The switch opens on when the exercise's slot already carries a program
    /// change (Q4).
    private func openSwap() {
        guard dialog == nil, case let .loaded(state) = workout,
              let index = WorkoutPresentation.shownExercise(of: state, selection: selection),
              WorkoutPresentation.canSwap(state.exercises[index])
        else {
            return
        }
        let exercise = state.exercises[index]
        swap = SwapState(
            exerciseIndex: index,
            exerciseID: exercise.exerciseID,
            alsoUpdateProgram: exercise.slotID.map { state.programUpdates[$0] != nil } ?? false
        )
        swapAttempt += 1
        dialog = .swap
    }

    /// Takes the sheet down when the workout `live` leaves its exercise unswappable: a set of it logged, by
    /// a tap that waited or by another hand, or another exercise in its place (criterion 25).
    func closeSwapIfStale(on live: WorkoutState) {
        guard dialog == .swap, let swap else {
            return
        }
        let isSwappable = live.exercises.indices.contains(swap.exerciseIndex)
            && live.exercises[swap.exerciseIndex].exerciseID == swap.exerciseID
            && WorkoutPresentation.canSwap(live.exercises[swap.exerciseIndex])
        if !isSwappable {
            dialog = nil
        }
    }

    /// Reads the alternatives for the current attempt (criterion 17): the shown exercise as stored, the
    /// catalog, the ranked list without the workout's other exercises (Q9), and each one's last session,
    /// from which its numbers are worked out as "Use" will apply them. A failed read is logged and shown,
    /// and opening the sheet again reads again; no load is guessed for a last session that could not be
    /// read (criterion 23).
    func loadSwap() async {
        guard let asked = swap, case .loading = asked.alternatives, case let .loaded(state) = workout,
              state.exercises.indices.contains(asked.exerciseIndex)
        else {
            return
        }
        let attempt = swapAttempt
        let current = state.exercises[asked.exerciseIndex]
        let result: Loadable<[SwapChoice]>
        do {
            result = try await .loaded(choices(replacing: current, in: state))
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                return
            }
            logger.log.error("The alternatives could not be read: \(String(describing: error), privacy: .public)")
            result = .failed(error)
        }
        // The first answer for this attempt is the one shown; an earlier attempt's is dropped.
        guard attempt == swapAttempt, case .loading = swap?.alternatives else {
            return
        }
        swap?.alternatives = result
    }

    private func choices(replacing current: WorkoutExercise, in state: WorkoutState) async throws -> [SwapChoice] {
        // A deleted custom exercise is no longer stored, and an unseeded catalog has nothing: no alternative.
        guard let stored = try await exercises.exercise(id: current.exerciseID) else {
            return []
        }
        let others = Set(state.exercises.map(\.exerciseID))
        let ranked = try await SwapAlternatives.ranked(for: stored, in: exercises.all(), excluding: others)
        var choices: [SwapChoice] = []
        for exercise in ranked {
            let last = try await stats.lastPerformance(exerciseID: exercise.id)
            choices.append(SwapChoice(
                replacing: current.exerciseID,
                exerciseID: exercise.id,
                name: exercise.name,
                replacement: SwapAlternatives.replacement(of: current, with: exercise, last: last, units: state.units)
            ))
        }
        return choices
    }

    /// The exercises of the workout on screen whose bests were never asked for: those a swap brought in,
    /// once the first read has answered. What the root's `.task(id:)` for `readSwappedBests()` follows.
    var unreadBests: Set<ExerciseID> {
        guard case .loaded = bests, case let .loaded(state) = workout else {
            return []
        }
        return Set(state.exercises.map(\.exerciseID)).subtracting(bestsAsked)
    }

    /// Reads the bests of the exercises a swap brought in, once each, and merges them into `bests` (S7b's
    /// input; criterion 27): a record on one is then felt as any other. The records they held when the
    /// read started are taken as held. A failed read is logged and not retried: an exercise with no bests
    /// sets no record.
    func readSwappedBests() async {
        let unread = unreadBests
        guard !unread.isEmpty, case let .loaded(state) = workout else {
            return
        }
        do {
            let read = try await stats.bests(before: state, for: unread)
            guard case var .loaded(merged) = bests else {
                return
            }
            for id in unread {
                merged.e1RM[id] = read.e1RM[id]
                merged.weightAtReps[id] = read.weightAtReps[id]
            }
            bestsAsked.formUnion(unread)
            bests = .loaded(merged)
            let held = records(of: state).filter { unread.contains($0.exerciseID) }
            heldRecords.formUnion(held.map(HeldRecord.init))
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                return
            }
            logger.log.error("The bests could not be read: \(String(describing: error), privacy: .public)")
            bestsAsked.formUnion(unread)
        }
    }
}
