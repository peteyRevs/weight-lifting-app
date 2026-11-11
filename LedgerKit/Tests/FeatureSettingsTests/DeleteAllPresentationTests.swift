@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import Testing

/// F14 S3, criterion 6 and N19, the presentation: the row with and without a workout in progress, the warning's words
/// (what goes and what stays, Pete's question 3), the sheet at each step, and the typed word's rule.
@Suite("Delete all data · presentation", .tags(.feature))
struct DeleteAllPresentationTests {
    @Test("The row opens the warning; while a workout is in progress it is off and says why")
    func row_followsTheLiveWorkout() {
        let open = DeleteAllPresentation.row(hasLiveWorkout: false)
        #expect(open.title == "Delete all data" && open.detail == nil && open.action == .deleteAll)
        let waiting = DeleteAllPresentation.row(hasLiveWorkout: true)
        #expect(waiting.detail == "Finish or discard your workout first" && waiting.action == nil)
    }

    @Test("Q3. The warning names what goes and what stays, Apple Health included; Cancel beside Continue")
    func warning_namesWhatGoesAndWhatStays() throws {
        #expect(DeleteAllPresentation.warning(nil) == nil)
        #expect(DeleteAllPresentation.warning(DeleteAllDraft(step: .typing)) == nil)
        let warning = try #require(DeleteAllPresentation.warning(DeleteAllDraft()))
        #expect(warning.title == "Delete all data?")
        #expect(warning.message == """
        This deletes every workout and set, your records, your programs and your custom exercises. Any exported files \
        on this iPhone go too, and your settings go back to how they started. The built-in exercise list is restored. \
        Workouts already saved to Apple Health stay there: delete them in the Health app.
        """)
        #expect(warning.cancel == SettingsModel.Link(title: "Cancel", action: .cancelDeleteAll))
        #expect(warning.proceed == SettingsModel.Link(title: "Continue", action: .continueDeleteAll))
    }

    @Test("The sheet: its words, the word typed as given, and Delete everything only once it matches and no erase runs")
    func sheet_atEachStep() throws {
        #expect(DeleteAllPresentation.sheet(DeleteAllDraft(), locale: Fixtures.locale) == nil)
        let empty = try #require(DeleteAllPresentation.sheet(DeleteAllDraft(step: .typing), locale: Fixtures.locale))
        #expect(empty.title == "Delete all data" && empty.cancel == "Cancel")
        #expect(empty.message == "This can't be undone." && empty.prompt == "Type DELETE to confirm")
        #expect(empty.word == "DELETE" && empty.text.isEmpty && empty.problem == nil)
        #expect(empty.confirmTitle == "Delete everything" && empty.confirm == nil && !empty.isErasing)
        let typed = DeleteAllPresentation.sheet(DeleteAllDraft(step: .typing, text: "delete "), locale: Fixtures.locale)
        #expect(typed?.text == "delete " && typed?.confirm == .confirmDeleteAll)
        let erasing = DeleteAllPresentation.sheet(
            DeleteAllDraft(step: .typing, text: "DELETE", isErasing: true),
            locale: Fixtures.locale
        )
        #expect(erasing?.confirm == nil && erasing?.isErasing == true)
        let failed = DeleteAllPresentation.sheet(
            DeleteAllDraft(step: .typing, text: "DELETE", failed: true),
            locale: Fixtures.locale
        )
        #expect(failed?.problem == "Nothing was deleted. Try again." && failed?.confirm == .confirmDeleteAll)
    }

    @Test(
        "Criterion 6.2. The word matches whatever its case and the spaces and line breaks around it, and nothing else",
        arguments: [
            ("DELETE", true), ("delete", true), ("dElEtE", true), (" DELETE", true), ("DELETE\n", true),
            ("\t delete \r\n", true), ("", false), ("   ", false), ("DELET", false), ("DELETES", false),
            ("DE LETE", false), ("DELETE DELETE", false), ("DELETE.", false), ("ДELETE", false)
        ]
    )
    func typedWord_rule(_ text: String, _ matches: Bool) {
        #expect(DeleteAllPresentation.matches(text, locale: Fixtures.locale) == matches)
    }
}
