@testable import LedgerDesign
import Testing

@Suite("LedgerDesign")
struct LedgerDesignTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerDesignModule.name == "LedgerDesign")
    }
}
