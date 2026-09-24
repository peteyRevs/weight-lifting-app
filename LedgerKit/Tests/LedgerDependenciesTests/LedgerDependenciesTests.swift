@testable import LedgerDependencies
import Testing

@Suite("LedgerDependencies")
struct LedgerDependenciesTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(LedgerDependenciesModule.name == "LedgerDependencies")
    }
}
