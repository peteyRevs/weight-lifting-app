@testable import LedgerAppKit
import Testing

/// F09 S1 criterion 4, the wording of the shell's copy. That it lives in the catalog and in no other file is not
/// this module's to test: `ModuleCopyTests` audits every module's sources and asks each built bundle for its
/// catalog's keys, and the gate compares each catalog with the compiler's keys.
@Suite("AppCopy")
struct AppCopyTests {
    @Test("The tabs are titled as product spec §2.1 titles them")
    func tabTitles_areTheSpecs() {
        #expect(AppTab.allCases.map(AppCopy.title(of:)) == ["Today", "Program", "Library", "History"])
    }

    @Test("Product decision #29's screen says what criterion 4 says, and does not name the product")
    func databaseUnavailable_saysWhatTheCriterionSays() {
        #expect(AppCopy.databaseUnavailableTitle == "Can't open your data right now")
        #expect(
            AppCopy.databaseUnavailableBody
                == "Your workouts are still on this iPhone. The app tries again when you come back to it."
        )
    }
}
