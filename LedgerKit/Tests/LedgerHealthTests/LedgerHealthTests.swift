@testable import LedgerHealth
import Testing

@Suite("LedgerHealth")
struct LedgerHealthTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerHealthModule.name == "LedgerHealth")
    }
}
