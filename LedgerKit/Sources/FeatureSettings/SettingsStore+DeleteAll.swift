import Foundation
import LedgerDomain

/// "Delete all data" (F14 S3, criterion 6, N19–N23; Pete's question 3, A): the warning, then the sheet that asks for
/// the typed word, then the erase.
///
/// **The steps.** The row opens the warning; its "Continue" opens the sheet; "Delete everything" acts only once the
/// typed word matches (`DeleteAllPresentation.matches`). "Cancel" at either step, or the sheet swiped away, deletes
/// nothing.
///
/// **A live workout** (N19): the store follows the session, and while a workout is in progress the row is off and a
/// warning or sheet already up is closed. The erase asks the session once more before it begins, so a workout started
/// in between is never erased under the lifter.
///
/// **The erase** runs once (N23): a second tap while it runs does nothing. It restores the settings a new install of
/// this region starts from (decision #15, `Settings.regional`), in the one write `DataReset` makes, then empties the
/// export's directory (N22). The app's gate then shows onboarding (C23), and Settings goes with the stack. A failure
/// keeps the sheet and says that nothing was deleted; a cancelled erase reports nothing, since the screen has gone.
extension SettingsStore {
    /// Applies `action` when it is "Delete all data"'s, and says whether it was.
    func sendToDeleteAll(_ action: SettingsAction) -> Bool {
        switch action {
        case .deleteAll:
            if !hasLiveWorkout, deleteAll == nil {
                deleteAll = DeleteAllDraft()
            }
        case .continueDeleteAll:
            if deleteAll?.step == .warning {
                deleteAll?.step = .typing
            }
        case let .setDeleteText(text):
            type(text)
        case .confirmDeleteAll:
            confirmErase()
        case .cancelDeleteAll:
            if deleteAll?.isErasing == false {
                deleteAll = nil
            }
        case .setUnits, .setDefaultRest, .setWeekStart, .setPlateMath, .setAutoRest, .setWatchBuzz, .editPlates,
             .setBar, .setPlate, .resetPlates, .savePlates, .cancelPlates, .route:
            return false
        }
        show()
        return true
    }

    /// The sheet's field, as typed, while no erase runs.
    private func type(_ text: String) {
        if deleteAll?.step == .typing, deleteAll?.isErasing == false {
            deleteAll?.text = text
        }
    }

    /// "Delete everything": the erase asked for, once, when the sheet's button acts (the typed word matches and no
    /// erase runs).
    private func confirmErase() {
        guard let draft = deleteAll, DeleteAllPresentation.sheet(draft, locale: locale)?.confirm != nil else {
            return
        }
        deleteAll?.isErasing = true
        deleteAll?.failed = false
        eraseMark?.yield()
    }

    /// Runs the erase each time it is asked for, in `run()`'s group.
    func erase(when marks: AsyncStream<Void>) async {
        for await _ in marks {
            await erase()
        }
    }

    /// Follows the live workout (N19): while one is in progress the row is off, and a warning or sheet not yet erasing
    /// is closed.
    func followWorkout() async {
        for await update in await session.updates() {
            let isLive = update.live != nil
            guard isLive != hasLiveWorkout else {
                continue
            }
            hasLiveWorkout = isLive
            if isLive, deleteAll?.isErasing == false {
                deleteAll = nil
            }
            show()
        }
    }

    /// The erase the sheet asked for, unless a workout is now in progress; then the export's directory emptied.
    private func erase() async {
        guard deleteAll?.isErasing == true else {
            return
        }
        do {
            if try await session.current() != nil {
                hasLiveWorkout = true
                deleteAll = nil
                show()
                return
            }
            try await reset.eraseAll(restoring: Settings.regional(locale: locale, calendar: calendar))
        } catch {
            deleteAll?.isErasing = false
            if !Task.isCancelled {
                logger.log.error("All data could not be deleted: \(String(describing: error))")
                deleteAll?.failed = true
            }
            show()
            return
        }
        await clearExports()
        deleteAll = nil
        show()
    }
}
