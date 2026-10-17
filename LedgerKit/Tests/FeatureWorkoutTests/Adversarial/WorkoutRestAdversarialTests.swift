import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S6 criteria 3, 4 and 7: the rest's time and its haptics on one phone, over the real host, with
/// the cover's tasks run as `WorkoutRoot` runs them (`RestCover`). The oracle is the session's workout and
/// the Domain (`RestTimer`, `ClockText`): at every instant the panel reads the wall clock's time left for
/// the rest the session shows, and each haptic is played exactly once.
@MainActor
@Suite("Workout rest (adversarial)", .tags(.feature), .timeLimit(.minutes(3)))
struct WorkoutRestAdversarialTests {
    /// What one seeded walk came to.
    struct Walk {
        var fault: String?
        var logs = 0
        var ends = 0
        var played: [Haptic] = []
        var covers = 1
    }

    /// One move of the walk that is not time going by: a tap on the page or the panel, the cover's tasks
    /// starting again, or the cover going down and up.
    static func act(_ move: Int, on cover: RestCover, showing shown: WorkoutState?) async {
        let cursor = shown?.cursor
        let exercise = cursor?.exerciseIndex ?? 0
        let row = cursor.flatMap { shown?.exercises[$0.exerciseIndex].sets[$0.setIndex] }
        let first = shown?.exercises[0].sets[0]
        switch (move, row) {
        case let (14 ..< 17, row?) where row.isDone:
            await cover.tap(.unlog(exerciseIndex: exercise, setID: row.id))
        case let (14 ..< 17, row?):
            await cover.tap(.log(exerciseIndex: exercise, setID: row.id))
        case (17 ..< 20, _):
            await cover.tap(.extendRest)
        case (20, _):
            await cover.tap(.skipRest)
        case (21, _):
            await cover.tap(.unlog(exerciseIndex: 0, setID: first?.id ?? SetID(Fixtures.uuid(0))))
        case let (22, row?):
            await cover.tap(.stepReps(exerciseIndex: exercise, setID: row.id, .increment))
        case (23 ..< 25, _):
            await cover.restartTasks()
        case (25, _):
            await cover.reopen()
        default:
            break
        }
    }

    /// A seeded walk: time going by a quarter of a second to 40 s at a step, the app away for up to 200 s,
    /// a main actor that wakes a little late, sets logged and un-logged, steppers, "+30s", "Skip rest", the
    /// cover's tasks starting again and the cover going down and up, in any order. After every step the
    /// panel is compared with what the session and the Domain owe; the ends of a rest that a buzz is owed
    /// for are counted (the wait that found it over ended less than a second after its end).
    static func walk(seed: UInt64, steps: Int = 70) async throws -> Walk {
        var generator = SplitMix64(seed: seed)
        // Every exercise rests 30 s, the shortest there is, so that most rests reach their end.
        var running = try Fixtures.seedSession()
        for index in running.exercises.indices {
            running.exercises[index].rest = RestDuration(clampingSeconds: 30)
        }
        let cover = try await RestCover(running)
        var walk = Walk()
        for step in 0 ..< steps {
            let before = cover.now
            let shown = await cover.truth()
            let rest = shown?.shownRest
            let move = Int.random(in: 0 ..< 26, using: &generator)
            // How long after the rest's end the wait that could find it over ended; nil when no time went by.
            var lateness: Double?
            if move < 10 {
                await cover.run([0.25, 0.5, 0.75, 1, 1.5, 3, 10, 20, 40, 40][move])
                lateness = 0
            } else if move < 14 {
                await cover.suspend([0.25, 0.75, 40, 200][move - 10])
                lateness = rest.map { cover.now.timeIntervalSince($0.endsAt) }
            } else {
                await Self.act(move, on: cover, showing: shown)
            }
            let after = await cover.truth()
            walk.logs += max(0, (after?.doneSets ?? 0) - (shown?.doneSets ?? 0))
            if let rest, let lateness, before < rest.endsAt, cover.now >= rest.endsAt, lateness < 1 {
                walk.ends += 1
            }
            if let fault = await cover.panelFault(), walk.fault == nil {
                walk.fault = "step \(step), move \(move): \(fault)"
            }
        }
        walk.played = await cover.played()
        walk.covers = cover.covers
        await cover.close()
        return walk
    }

    @Test(
        "A seeded walk: at every step the panel reads the wall clock's time left, and each haptic is played once",
        arguments: RestSeeds.all
    )
    func walk_panelAndHaptics(seed: UInt64) async throws {
        let walk = try await Self.walk(seed: seed)
        #expect(walk.fault == nil, "seed \(seed)")
        #expect(walk.played.count { $0 == .setLogged } == walk.logs, "seed \(seed): one for each logged set")
        #expect(
            walk.played.count { $0 == .restOver } == walk.ends,
            "seed \(seed): one for each rest that ended on time"
        )
        #expect(walk.played.count == walk.logs + walk.ends, "seed \(seed): and nothing else")
    }

    @Test("The walks do enough to tell: rests end on time, late and never, and the cover goes down and up")
    func walk_isNotVacuous() async throws {
        var (logs, ends, covers) = (0, 0, 0)
        for seed in RestSeeds.all.prefix(12) {
            let walk = try await Self.walk(seed: seed)
            logs += walk.logs
            ends += walk.ends
            covers += walk.covers
        }
        // The first 40 seeds give 325 logged sets, 97 rests that end on time and 156 covers.
        #expect(logs >= 40)
        #expect(ends >= 10)
        #expect(covers >= 20)
    }
}
