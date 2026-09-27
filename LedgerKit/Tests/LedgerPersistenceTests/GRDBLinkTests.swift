import GRDB
@testable import LedgerPersistence
import Testing

@Suite("GRDB linkage")
struct GRDBLinkTests {
    @Test
    func `GRDB links and opens an in-memory queue on every platform we ship`() throws {
        let queue = try DatabaseQueue()
        let answer = try queue.read { database in try Int.fetchOne(database, sql: "SELECT 1") }
        #expect(answer == 1)
    }
}
