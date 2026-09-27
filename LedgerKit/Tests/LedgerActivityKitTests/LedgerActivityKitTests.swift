@testable import LedgerActivityKit
import Testing

@Suite("LedgerActivityKit")
struct LedgerActivityKitTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerActivityKitModule.name == "LedgerActivityKit")
    }
}
