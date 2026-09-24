@testable import LedgerDomain
import Testing

@Suite("LedgerDomain")
struct LedgerDomainTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerDomainModule.name == "LedgerDomain")
    }
}
