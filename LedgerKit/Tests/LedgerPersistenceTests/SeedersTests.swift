import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// `Seeders.program` and `Seeders.slot` are public and later features reuse them, so a shape they cannot build
/// throws `UnsupportedShape` rather than trapping or giving two slots one id (review N5).
@Suite("Seeders", .tags(.persistence))
struct SeedersTests {
    static let exercises = Seeders.catalog(count: 3, version: 1).exercises.map(\.id)

    @Test("A shape outside the documented ranges throws, naming the parameter")
    func unsupportedShapes_throw() {
        let shapes: [(Seeders.UnsupportedShape, () throws -> Void)] = [
            (.init(parameter: "days", value: 8), { _ = try Seeders.program(days: 8, exercises: Self.exercises) }),
            (.init(parameter: "days", value: -1), { _ = try Seeders.program(days: -1, exercises: Self.exercises) }),
            (.init(parameter: "slotsPerDay", value: 33), {
                _ = try Seeders.program(slotsPerDay: 33, exercises: Self.exercises)
            }),
            (.init(parameter: "exercises", value: 0), { _ = try Seeders.program(exercises: []) }),
            (.init(parameter: "position", value: 32), {
                _ = try Seeders.slot(0, day: 0, position: 32, last: false, Self.exercises)
            })
        ]
        for (expected, build) in shapes {
            #expect(throws: expected) { try build() }
        }
    }

    @Test("The largest shapes build, with every slot id distinct")
    func largestShapes_build() throws {
        let program = try Seeders.program(days: 7, slotsPerDay: 32, exercises: Self.exercises)
        let slotIDs = program.days.flatMap(\.slots).map(\.id)
        #expect(Set(slotIDs).count == 7 * 32)
        #expect(Set(program.weeks[0].schedule.values).count == 7)
    }
}
