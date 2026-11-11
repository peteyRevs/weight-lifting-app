import LedgerDomain

/// "Delete all data" from the row's tap until the erase is done or cancelled (F14 S3, criterion 6): the warning first,
/// then the sheet that asks for the typed word, what is typed, and whether the erase runs or failed.
nonisolated struct DeleteAllDraft: Hashable, Sendable {
    enum Step: Hashable, Sendable {
        /// The alert: what goes and what stays, "Cancel" or "Continue".
        case warning
        /// The sheet: the word typed, then "Delete everything".
        case typing
    }

    var step = Step.warning
    var text = ""
    /// The erase was asked for and has not returned: nothing on the sheet acts (N23).
    var isErasing = false
    /// The last erase threw: nothing was deleted, and the sheet says so.
    var failed = false
}

/// "Delete all data", the last row of DATA: it opens the warning, or, while a workout is in progress, is drawn switched
/// off, its line saying why (N19).
nonisolated struct DeleteAllRowModel: Equatable, Sendable {
    let title: String
    /// "Finish or discard your workout first" while it is off; nil otherwise.
    let detail: String?
    /// Opens the warning; nil while a workout is in progress.
    let action: SettingsAction?
}

/// The warning, the system's alert: its title, what goes and what stays, and its two buttons, "Cancel" beside
/// "Continue", which is destructive.
nonisolated struct DeleteAllWarning: Equatable, Sendable {
    let title: String
    let message: String
    let cancel: SettingsModel.Link
    let proceed: SettingsModel.Link
}

/// The sheet that asks for the typed word, as `DeleteAllPresentation.sheet` makes it.
nonisolated struct DeleteAllSheetModel: Equatable, Sendable, Identifiable {
    /// One sheet: it stays the same sheet while what is typed changes (`.sheet(item:)`).
    let id = 0
    let title: String
    let cancel: String
    /// "This can't be undone."
    let message: String
    /// "Type DELETE to confirm": the field's label, and what VoiceOver reads for it.
    let prompt: String
    /// "DELETE", in the lifter's language: the field's placeholder.
    let word: String
    /// What is typed.
    let text: String
    /// "Nothing was deleted. Try again." after an erase failed; nil otherwise.
    let problem: String?
    /// "Delete everything".
    let confirmTitle: String
    /// The erase; nil, and the button dimmed, until the typed word matches, and while the erase runs.
    let confirm: SettingsAction?
    /// The erase runs: the field and Cancel do nothing, and the sheet cannot be swiped away.
    let isErasing: Bool
}
