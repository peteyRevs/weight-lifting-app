@testable import LedgerPersistence
import Testing

@Suite("LedgerPersistence")
struct LedgerPersistenceTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerPersistenceModule.name == "LedgerPersistence")
    }
}
