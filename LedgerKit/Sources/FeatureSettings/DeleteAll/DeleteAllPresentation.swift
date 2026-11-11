import Foundation
import LedgerDomain

/// "Delete all data"'s logic and its words (F14 S3, criterion 6, N19), in pure steps the store and
/// `SettingsPresentation` call: the row, the warning while it is up, the sheet while it is up, and whether the typed
/// word matches.
nonisolated enum DeleteAllPresentation {
    static func row(hasLiveWorkout: Bool) -> DeleteAllRowModel {
        DeleteAllRowModel(
            title: SettingsCopy.deleteAll,
            detail: hasLiveWorkout ? SettingsCopy.deleteAllWaits : nil,
            action: hasLiveWorkout ? nil : .deleteAll
        )
    }

    /// The warning, while `draft` is at it.
    static func warning(_ draft: DeleteAllDraft?) -> DeleteAllWarning? {
        guard draft?.step == .warning else {
            return nil
        }
        return DeleteAllWarning(
            title: SettingsCopy.deleteAllQuestion,
            message: [
                SettingsCopy.deleteAllWhatGoes,
                SettingsCopy.deleteAllWhatElseGoes,
                SettingsCopy.deleteAllCatalogStays,
                SettingsCopy.deleteAllHealthStays
            ].joined(separator: " "),
            cancel: SettingsModel.Link(title: SettingsCopy.cancel, action: .cancelDeleteAll),
            proceed: SettingsModel.Link(title: SettingsCopy.deleteAllContinue, action: .continueDeleteAll)
        )
    }

    /// The sheet, while `draft` is at it: "Delete everything" acts once the typed word matches and while no erase runs.
    static func sheet(_ draft: DeleteAllDraft?, locale: Locale) -> DeleteAllSheetModel? {
        guard let draft, draft.step == .typing else {
            return nil
        }
        let word = SettingsCopy.deleteWord
        return DeleteAllSheetModel(
            title: SettingsCopy.deleteAll,
            cancel: SettingsCopy.cancel,
            message: SettingsCopy.deleteAllCannotBeUndone,
            prompt: SettingsCopy.deleteAllPrompt(word, locale: locale),
            word: word,
            text: draft.text,
            problem: draft.failed ? SettingsCopy.deleteAllFailed : nil,
            confirmTitle: SettingsCopy.deleteEverything,
            confirm: !draft.isErasing && matches(draft.text, locale: locale) ? .confirmDeleteAll : nil,
            isErasing: draft.isErasing
        )
    }

    /// Whether `text`, without the spaces and line breaks around it, is the localized word ("DELETE"), in any case as
    /// `locale` folds it: "delete" and " Delete " match, "DELET" and "DELETE IT" do not (criterion 6.2).
    static func matches(_ text: String, locale: Locale) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(SettingsCopy.deleteWord, options: .caseInsensitive, range: nil, locale: locale) == .orderedSame
    }
}
