@testable import LedgerWatchAppKit
import Testing

@Suite("LedgerWatchAppKit")
struct LedgerWatchAppKitTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerWatchAppKitModule.name == "LedgerWatchAppKit")
    }
}
