import Foundation
import LedgerDomain

/// The words of "Delete all data" (F14 S3, criterion 6; Pete's question 3, A: a warning, then the typed word).
nonisolated extension SettingsCopy {
    static var deleteAll: String {
        String(
            localized: "Delete all data",
            bundle: .module,
            comment: "Settings row that erases the whole log; also the title of the sheet that confirms it"
        )
    }

    /// Under the row while it is off (N19).
    static var deleteAllWaits: String {
        String(
            localized: "Finish or discard your workout first",
            bundle: .module,
            comment: "Under Delete all data in Settings while a workout is in progress, which keeps it off"
        )
    }

    static var deleteAllQuestion: String {
        String(
            localized: "Delete all data?",
            bundle: .module,
            comment: "Title of the warning Delete all data opens"
        )
    }

    // The warning's message (Pete's question 3), four sentences `DeleteAllPresentation` joins: what goes, what
    // else goes, and what stays, Apple Health included.

    static var deleteAllWhatGoes: String {
        String(
            localized: "This deletes every workout and set, your records, your programs and your custom exercises.",
            bundle: .module,
            comment: "Delete all data warning, its first sentence: what is deleted"
        )
    }

    static var deleteAllWhatElseGoes: String {
        String(
            localized: "Any exported files on this iPhone go too, and your settings go back to how they started.",
            bundle: .module,
            comment: "Delete all data warning, its second sentence: what else is deleted or reset"
        )
    }

    static var deleteAllCatalogStays: String {
        String(
            localized: "The built-in exercise list is restored.",
            bundle: .module,
            comment: "Delete all data warning, its third sentence: the built-in catalog is put back as it ships"
        )
    }

    static var deleteAllHealthStays: String {
        String(
            localized: "Workouts already saved to Apple Health stay there: delete them in the Health app.",
            bundle: .module,
            comment: "Delete all data warning, its last sentence: Apple Health is not touched"
        )
    }

    static var deleteAllContinue: String {
        String(
            localized: "Continue",
            bundle: .module,
            comment: "Delete all data warning: goes on to the sheet that asks for the typed word"
        )
    }

    static var deleteAllCannotBeUndone: String {
        String(
            localized: "This can't be undone.",
            bundle: .module,
            comment: "Delete all data sheet: above the field for the typed word"
        )
    }

    /// The word typed to confirm. The store compares what is typed with this word, ignoring case, so a translation is
    /// one word the lifter's keyboard types easily.
    static var deleteWord: String {
        String(
            localized: "DELETE",
            bundle: .module,
            comment: "The word typed to confirm Delete all data, in capitals; one word a keyboard types easily"
        )
    }

    /// "Type DELETE to confirm": the field's label, `word` being `deleteWord`.
    static func deleteAllPrompt(_ word: String, locale: Locale) -> String {
        String(
            localized: "Type \(word) to confirm",
            bundle: .module,
            locale: locale,
            comment: "Label of the Delete all data field; the word is the one to type (DELETE)"
        )
    }

    static var deleteEverything: String {
        String(
            localized: "Delete everything",
            bundle: .module,
            comment: "Delete all data sheet: erases the whole log, once the word is typed"
        )
    }

    static var deleteAllFailed: String {
        String(
            localized: "Nothing was deleted. Try again.",
            bundle: .module,
            comment: "Delete all data sheet, after the erase failed: nothing changed"
        )
    }
}
