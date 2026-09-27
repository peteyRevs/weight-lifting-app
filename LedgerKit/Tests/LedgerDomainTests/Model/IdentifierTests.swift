import Foundation
@testable import LedgerDomain
import Testing

@Suite("Identifiers", .tags(.domain))
struct IdentifierTests {
    @Test("Typed IDs encode as a bare UUID string and decode back")
    func codable_bareUUIDString() throws {
        let id = ExerciseID(Fixtures.uuid(42))
        let data = try JSONEncoder().encode(id)
        #expect(try Fixtures.json(id) == #""00000000-0000-0000-0000-00000000002A""#)
        #expect(try JSONDecoder().decode(ExerciseID.self, from: data) == id)
    }

    @Test("Every identifier type wraps its UUID")
    func everyType_wrapsRawValue() {
        let raw = Fixtures.uuid(7)
        let values: [UUID] = [
            ExerciseID(raw).rawValue, ProgramID(raw).rawValue, WeekID(raw).rawValue, DayTemplateID(raw).rawValue,
            SlotID(raw).rawValue, WorkoutID(raw).rawValue, WorkoutExerciseID(raw).rawValue, SetID(raw).rawValue,
            DeviceID(raw).rawValue
        ]
        #expect(values.allSatisfy { $0 == raw })
    }

    @Test("Derived child IDs are deterministic, distinct and version 8")
    func derived_deterministicDistinctV8() {
        let workout = WorkoutID(Fixtures.uuid(1))
        let exercises = (0 ..< 20).map { WorkoutExerciseID.derived(from: workout, index: $0) }
        let sets = exercises.flatMap { exercise in (0 ..< 12).map { SetID.derived(from: exercise, index: $0) } }
        #expect(exercises == (0 ..< 20).map { WorkoutExerciseID.derived(from: workout, index: $0) })
        #expect(Set(exercises).count == exercises.count)
        #expect(Set(sets.map(\.rawValue)).count == sets.count)
        #expect(Set(sets.map(\.rawValue)).isDisjoint(with: exercises.map(\.rawValue)))
        let other = WorkoutExerciseID.derived(from: WorkoutID(Fixtures.uuid(2)), index: 0)
        #expect(other != exercises[0])
        for id in exercises.map(\.rawValue) + sets.map(\.rawValue) {
            #expect(id.uuid.6 >> 4 == 8, "version nibble of \(id)")
            #expect(id.uuid.8 >> 6 == 0b10, "variant bits of \(id)")
        }
    }
}
