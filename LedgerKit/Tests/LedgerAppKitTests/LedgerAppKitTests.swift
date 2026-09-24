@testable import LedgerAppKit
import Testing

@Suite("LedgerAppKit")
struct LedgerAppKitTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerAppKitModule.name == "LedgerAppKit")
    }
}
