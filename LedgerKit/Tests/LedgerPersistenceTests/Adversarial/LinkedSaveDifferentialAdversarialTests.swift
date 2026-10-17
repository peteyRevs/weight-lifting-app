import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 6: "the in-memory stores apply the same rules, refuse what the
/// database refuses in the same order". Seeded scripts of saves and program edits run on the database and on
/// LedgerFakes' linked stores at once: the two must answer alike and hold the same after every step, and
/// both must hold what `LinkedModel` (criteria 1 to 4, written here) holds. A failing case names its seed.
@Suite(
    "Adversarial F10 S3 · the database, the fakes and a model",
    .tags(.persistence, .property),
    .timeLimit(.minutes(1))
)
struct LinkedSaveDifferentialAdversarialTests {
    typealias Fixture = LinkedFixture

    /// Every seed of the lane in the nightly plans, six elsewhere: enough to reach every rule
    /// (`scripts_reachEveryRule`), at about a fifth of a second a script on the simulator.
    static let seeds = Array(PropertySeed.all.prefix(TestLane.runsSlowTests ? PropertySeed.all.count : 6))

    @Test("A seeded script of saves: the database, the fakes and the model agree after every step", arguments: seeds)
    func script_databaseFakesAndModel_agree(seed: PropertySeed) async throws {
        let difference = try await LinkedScriptRun.difference(seed: seed.value)
        #expect(difference == nil, "\(seed): \(difference ?? "")")
    }

    @Test("The scripts reach what they claim: updates applied and skipped for each reason, logs dropped and kept")
    func scripts_reachEveryRule() throws {
        var seen: Set<String> = []
        for seed in Self.seeds {
            var writer = LinkedScriptWriter(seed: seed.value)
            var stored: Set = [1, 2]
            for _ in 0 ..< 30 {
                switch try writer.step() {
                case let .save(workout, slots, droppingLog):
                    seen.insert(droppingLog ? "log dropped" : "log kept")
                    seen.insert(slots.isEmpty ? "no misses" : "misses")
                    for (slot, exercise) in workout.programUpdates {
                        try seen.insert(Self.kind(slot, exercise, of: workout, stored: stored))
                    }
                case let .deleteProgram(number): stored.remove(number)
                case let .restoreProgram(number): stored.insert(number)
                case .log, .removeSlot: seen.insert("an edit or a log")
                }
            }
        }
        let wanted: Set = [
            "log dropped", "log kept", "misses", "no misses", "an edit or a log", "own slot", "ad hoc",
            "another program's slot", "a slot that never was", "an exercise that is not stored",
            "the exercise it holds", "a deleted program"
        ]
        #expect(wanted.subtracting(seen).isEmpty, "never reached: \(wanted.subtracting(seen).sorted())")
    }

    /// The rule an update of a script meets, for `scripts_reachEveryRule`.
    static func kind(
        _ slot: SlotID,
        _ exercise: ExerciseID,
        of workout: WorkoutState,
        stored: Set<Int>
    ) throws -> String {
        guard let source = workout.source else {
            return "ad hoc"
        }
        let own = source.programID == S2Kit.programID(1) ? 1 : 2
        guard stored.contains(own) else {
            return "a deleted program"
        }
        guard slot != Fixture.unknownSlot else {
            return "a slot that never was"
        }
        guard let built = try Fixture.program(own).days.flatMap(\.slots).first(where: { $0.id == slot }) else {
            return "another program's slot"
        }
        if exercise == Fixture.unknownExercise {
            return "an exercise that is not stored"
        }
        return exercise == built.exerciseID ? "the exercise it holds" : "own slot"
    }

    /// Two reasons to refuse one workout at once: which one a store names is the order it checks in.
    static func doubleFaults() throws -> [(name: String, workout: WorkoutState)] {
        let singles = try LinkedSaveLogAdversarialTests.refused()
        var pairs: [(String, WorkoutState)] = []
        for (first, one) in singles.enumerated() {
            for (_, other) in singles.enumerated().dropFirst(first + 1) {
                var both = one.workout
                both.phase = other.workout.phase == .live ? .live : both.phase
                both.endedAt = other.workout.endedAt == nil ? nil : both.endedAt
                both.name = other.workout.name.contains("\u{0}") ? other.workout.name : both.name
                if other.name == "an eighth of a pound" {
                    both.exercises[0].sets[1].weight = .pounds(0.125)
                }
                if other.name == "a set id twice" {
                    both.exercises[1].sets[1] = other.workout.exercises[1].sets[1]
                }
                pairs.append(("\(one.name) and \(other.name)", both))
            }
        }
        return singles.map { ($0.name, $0.workout) } + pairs
    }

    @Test("A workout refused for one reason or two is refused for the same reason by both kinds of store")
    func refusals_databaseAndFakes_nameTheSameReason() async throws {
        let (database, memory) = try await (LinkedStores.make(.database), LinkedStores.make(.memory))
        let held = Fixture.workout(7)
        for stores in [database, memory] {
            #expect(await stores.save(held, droppingLog: false) == "false")
        }
        var cases = try Self.doubleFaults()
        var taken = Fixture.workout(8)
        taken.exercises[0].sets[0] = held.exercises[0].sets[0]
        cases.append(("a set id another workout holds", taken))
        for (name, workout) in cases {
            let answers = await [database.save(workout, droppingLog: true), memory.save(workout, droppingLog: true)]
            #expect(
                answers[0] == answers[1],
                "\(name): the database says \(answers[0].prefix(70)), the fakes \(answers[1].prefix(70))"
            )
            #expect(answers[0] != "true", "\(name) was saved")
            let issue = try await LinkedComparison.difference(database, memory)
            #expect(issue == nil, "\(name): \(issue ?? "")")
        }
        #expect(try await database.workouts.recent(limit: 99).map(\.id) == [held.id], "nothing refused was stored")
    }
}
