import Foundation
import LedgerDomain

/// The receipt of `WorkoutStore` (F10 S7b): the workout this cover saved, its records, "Done", and the
/// live record's haptic. In a file of its own for its length; the members of the store it uses are the
/// store's alone.
///
/// **Which workout shows a receipt.** One that the save running in this cover ended: the session was
/// asked to finish it, and it is finished at the end the save asked for. It comes from `finish`'s return
/// or from the stream's ending update, whichever reaches the store first, and is set once. A workout
/// finished by another hand closes the cover as saved, with no receipt (S4's row S10), and so does a save
/// whose finished state never reached the store (criterion 18's third outcome; product default O7).
///
/// **The bests** are read once, when the cover first shows the workout (`readBests()`, from the root's
/// task): the records of the receipt are judged against them, and so is each set logged meanwhile. A
/// read that fails is logged and not retried; the receipt then shows no records line, as it does until
/// the read answers.
extension WorkoutStore {
    /// The receipt of the workout this cover saved; nil until it is saved.
    var receipt: ReceiptScreenModel? {
        saved.map { WorkoutPresentation.receipt($0, records: records(of: $0), locale: locale, calendar: calendar) }
    }

    /// The workout `readBests()` reads for: the one on screen, once there is one.
    var bestsSubject: WorkoutID? {
        if case let .loaded(state) = workout {
            return state.id
        }
        return nil
    }

    /// Whether `ended` is the workout the save running in this cover ended: then its receipt shows. It is
    /// finished, it is the workout being saved, and its end is one this cover asked the session for
    /// (`askedEnds`): this attempt's, or an earlier one's that the host kept and completes now (a refused
    /// save, "Close", then "Save workout" again). An end another hand made, before the call or under it
    /// (`noLiveWorkout`), is not this cover's. `finish`'s answer and the ending update are judged by this
    /// alone, so the order they arrive in never changes the outcome (F10 S7b, fix round 1).
    func isSavedHere(_ ended: WorkoutState) -> Bool {
        if let saved {
            return saved.id == ended.id
        }
        guard isSaving, let save = pendingSave, let end = ended.endedAt else {
            return false
        }
        return ended.phase == .finished && ended.id == save.id && askedEnds.contains(end)
    }

    /// Whether the ending update `ended`, at an end this cover did not ask for, waits for `finish`'s answer:
    /// the workout being saved finished while this cover's call is out and no receipt is up yet. A finished
    /// answer then makes it this cover's save (the session kept an end of its own); `noLiveWorkout` makes it
    /// another hand's.
    func waitsForTheAnswer(_ ended: WorkoutState) -> Bool {
        saved == nil && exit == nil && isSaving && finishesInFlight > 0 && ended.phase == .finished
            && ended.id == pendingSave?.id
    }

    /// Shows the receipt of `ended`, once; the cover stays up until "Done". The sheet goes down, nothing
    /// waits any more, and with no live workout no rest is shown (criterion 37).
    func showReceipt(_ ended: WorkoutState) {
        guard saved == nil, exit == nil else {
            return
        }
        dialog = nil
        emptyQueue()
        exitWhenDrained = nil
        isSaving = false
        saved = ended
        settled?.wake.yield()
    }

    /// "Done": the cover closes as saved, and the app selects Today.
    func closeReceipt() {
        if let saved {
            leave(.route(.saved(saved.id)))
        }
    }

    /// The records `workout` set against the bests before it; none while the bests are not known.
    /// `now` is the start, as the store stamps a stored record (brief, Inputs from F05, item 3).
    func records(of workout: WorkoutState) -> [PersonalRecord] {
        guard case let .loaded(bests) = bests else {
            return []
        }
        return PersonalRecords.detect(workout: workout, against: bests, now: workout.startedAt)
    }

    /// Reads the bests the workout on screen is judged against, once for the store. The records the
    /// workout held when the read started are taken as held, and are never played (criterion 36).
    func readBests() async {
        guard case .idle = bests, case let .loaded(state) = workout else {
            return
        }
        do {
            let read = try await stats.bests(before: state, for: Set(state.exercises.map(\.exerciseID)))
            guard case .idle = bests else {
                return
            }
            bests = .loaded(read)
            // The records of the workout the read was made for: one set while the read was out is felt at
            // the next update (F10 S7b, fix round 1).
            heldRecords = Set(records(of: state).map(HeldRecord.init))
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                return
            }
            logger.log.error("The bests could not be read: \(String(describing: error), privacy: .public)")
            if case .idle = bests {
                bests = .failed(error)
            }
        }
    }

    /// `.personalRecord` once for each record `live` holds that the workout did not hold before, in the
    /// store's life: an un-log and a second log of the same set do not play it again. Only `follow()`
    /// plays it.
    func recordHaptics(in live: WorkoutState) -> [Haptic] {
        guard case .loaded = bests else {
            return []
        }
        let new = Set(records(of: live).map(HeldRecord.init)).subtracting(heldRecords)
        heldRecords.formUnion(new)
        return Array(repeating: .personalRecord, count: new.count)
    }
}

/// A record as the live haptic tells one from another: the exercise, and which of the two kinds.
nonisolated struct HeldRecord: Hashable, Sendable {
    let exerciseID: ExerciseID
    let isEstimate: Bool

    init(_ record: PersonalRecord) {
        exerciseID = record.exerciseID
        if case .estimatedOneRepMax = record.kind {
            isEstimate = true
        } else {
            isEstimate = false
        }
    }
}
