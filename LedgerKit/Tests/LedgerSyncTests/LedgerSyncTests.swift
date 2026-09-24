@testable import LedgerSync
import Testing

@Suite("LedgerSync")
struct LedgerSyncTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerSyncModule.name == "LedgerSync")
    }
}
