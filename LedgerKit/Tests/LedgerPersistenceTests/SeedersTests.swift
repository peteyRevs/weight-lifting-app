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

    @Test("A seeded history is finished workouts 42 hours apart, of the size asked for, the same for one seed")
    func history_isDeterministic_andSized() {
        let catalog = Seeders.catalog(count: 12, version: 1).exercises
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        var other = SeededGenerator(seed: 43)
        let history = Seeders.history(exercises: catalog, workouts: 40, setsPerWorkout: 50, rng: &first)
        #expect(history == Seeders.history(exercises: catalog, workouts: 40, setsPerWorkout: 50, rng: &second))
        #expect(history != Seeders.history(exercises: catalog, workouts: 40, setsPerWorkout: 50, rng: &other))
        #expect(history.count == 40)
        #expect(history.allSatisfy { $0.totalSets == 50 && $0.exercises.count == 5 && $0.phase == .finished })
        #expect(Set(history.map(\.id)).count == 40)
        #expect(Set(history.flatMap(\.exercises).flatMap(\.sets).map(\.id)).count == 2000)
        #expect(history.last?.endedAt == EventBuilders.start)
        #expect(history.first?.endedAt == EventBuilders.start.addingTimeInterval(-39 * 42 * 3600))
        let sets = history.flatMap(\.exercises).flatMap(\.sets)
        #expect(sets.contains { $0.kind == .drop } && sets.contains { !$0.isDone })
        #expect(sets.allSatisfy { $0.reps.value <= 15 && $0.weight >= .pounds(45) && $0.weight <= .pounds(315) })
    }

    @Test("A history of fewer exercises than five, of none, or of no workouts still builds")
    func history_smallShapes_build() {
        var generator = SeededGenerator(seed: 1)
        let two = Array(Seeders.catalog(count: 2, version: 1).exercises)
        let small = Seeders.history(exercises: two, workouts: 3, setsPerWorkout: 5, rng: &generator)
        #expect(small.map(\.totalSets) == [5, 5, 5])
        #expect(small.allSatisfy { $0.exercises.map(\.sets.count) == [3, 2] })
        let empty = Seeders.history(exercises: [], workouts: 2, setsPerWorkout: 5, rng: &generator)
        #expect(empty.map(\.exercises.count) == [0, 0])
        #expect(Seeders.history(exercises: two, workouts: -1, setsPerWorkout: 5, rng: &generator).isEmpty)
    }
}
