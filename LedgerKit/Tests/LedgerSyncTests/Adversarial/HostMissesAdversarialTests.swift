import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 4: "the workout is materialised (with the slots' misses from
/// `MissTracking`, applied to the program as stored at that moment and only when the active program is the
/// workout's)". The workout is the seed program's Upper A, built by `SessionBuilder`; the expected misses are
/// `MissTracking.update` run here on the program read from the store just before the finish.
@Suite("Adversarial F10 S2 · misses at finish", .tags(.sync), .timeLimit(.minutes(1)))
struct HostMissesAdversarialTests {
    typealias Backing = SiegeRig.Backing
    typealias Misses = [SlotID: Set<Int>]

    /// A host with Upper A of week `weekIndex` live: the first exercise done as prescribed, the second one
    /// set short, the third done with a rep too few, the rest untouched.
    static func scene(_ backing: Backing, weekIndex: Int = 4) async throws -> SiegeScene {
        let program = try Fixtures.seedProgram()
        let catalog = try ExerciseCatalog.seed()
        let seed = InMemoryStores.Seed(catalog: catalog, programs: [program])
        let session = try SessionBuilder.build(
            program: program, weekIndex: weekIndex, day: program.days[0],
            exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) }),
            history: [:], settings: Fixtures.settingsLb, id: Seam.workout(1), device: EventBuilders.phone,
            now: EventBuilders.start
        )
        let scene = try await SiegeScene.make(backing, seed: seed, session: session)
        for (exerciseIndex, rows, short) in [(0, 2 ..< 5, 0), (1, 0 ..< 2, 0), (2, 0 ..< 4, 1)] {
            let sets = session.exercises[exerciseIndex].sets
            for set in sets[rows.clamped(to: sets.indices)] {
                try await scene.host.apply(.setLogged(
                    exerciseIndex: exerciseIndex,
                    setID: set.id,
                    weight: set.weight,
                    reps: Reps(clamping: set.reps.value - short),
                    doneAt: Seam.at(900)
                ))
            }
        }
        return scene
    }

    static func misses(_ program: Program?) -> Misses {
        Dictionary(uniqueKeysWithValues: (program?.days ?? []).flatMap(\.slots).map { ($0.id, $0.misses) })
    }

    /// Rule 13 on `program` for the workout as it will finish: each slot the workout performed takes
    /// `MissTracking.update`; every other slot keeps its misses.
    static func expected(on program: Program?, after workout: WorkoutState) -> Misses {
        var misses = misses(program)
        for slot in (program?.days ?? []).flatMap(\.slots) {
            guard let exercise = workout.exercises.first(where: { $0.slotID == slot.id }) else {
                continue
            }
            misses[slot.id] = MissTracking.update(
                slot: slot, exercise: exercise, weekIndex: workout.source?.weekIndex ?? 0, isDeload: workout.isDeload
            ).misses
        }
        return misses
    }

    @Test("The active program's slots take the workout's misses", arguments: Backing.allCases)
    func finish_activeProgram_writesEachSlotsMisses(backing: Backing) async throws {
        let scene = try await Self.scene(backing)
        let standing = try #require(try await scene.host.current())
        let stored = try await scene.rig.programs.active()
        let wanted = Self.expected(on: stored, after: standing)
        let slots = try Fixtures.upperA().slots.map(\.id)
        #expect(slots.map { wanted[$0] } == [[], [4], [4], [4], [4]], "the fixture misses four of five slots")
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await Self.misses(scene.rig.programs.active()) == wanted)
        #expect(try await scene.rig.history().map(\.id) == [standing.id])
    }

    @Test(
        "Misses recorded since the workout started are kept: the program is read at the finish",
        arguments: Backing.allCases
    )
    func finish_missesRecordedSince_areKept(backing: Backing) async throws {
        let scene = try await Self.scene(backing)
        var program = try #require(try await scene.rig.programs.active())
        program.days[0].slots[0].misses = [1, 2, 4]
        program.days[0].slots[1].misses = [0]
        program.days[1].slots[0].misses = [3]
        try await scene.rig.programs.save(program)
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        let after = try await Self.misses(scene.rig.programs.active())
        #expect(after[program.days[0].slots[0].id] == [1, 2], "made this week: its own miss goes, the others stay")
        #expect(after[program.days[0].slots[1].id] == [0, 4])
        #expect(after[program.days[1].slots[0].id] == [3], "a slot the workout never performed is untouched")
    }

    @Test(
        "Another program is active at the finish: no slot of either is written, and the workout is saved",
        arguments: Backing.allCases
    )
    func finish_anotherProgramActive_writesNoMisses(backing: Backing) async throws {
        let scene = try await Self.scene(backing)
        let mine = try #require(try await scene.rig.programs.active())
        let catalog = try ExerciseCatalog.seed().map(\.id)
        var other = try Seeders.program(number: 3, exercises: Array(catalog.prefix(6)))
        other.days[0].slots[0].misses = [2]
        try await scene.rig.programs.save(other)
        let before = try await Self.misses(scene.rig.programs.active())
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await Self.misses(scene.rig.programs.active()) == before)
        try await scene.rig.programs.setActive(mine.id)
        #expect(
            try await Self.misses(scene.rig.programs.active()) == Self.misses(mine),
            "its misses were not the active program's to take"
        )
        #expect(try await scene.rig.history().count == 1)
    }

    @Test("The program was deleted during the workout: the workout is saved all the same", arguments: Backing.allCases)
    func finish_programDeleted_savesTheWorkout(backing: Backing) async throws {
        let scene = try await Self.scene(backing)
        try await scene.rig.programs.delete(Fixtures.programID)
        let finished = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self))
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.siege.saved.last?.slots.isEmpty == true)
    }

    @Test("A slot that is no longer stored is skipped; the others take their misses", arguments: Backing.allCases)
    func finish_slotNoLongerStored_isSkipped(backing: Backing) async throws {
        let scene = try await Self.scene(backing)
        var program = try #require(try await scene.rig.programs.active())
        program.days[0].slots.remove(at: 1)
        try await scene.rig.programs.save(program)
        let standing = try #require(try await scene.host.current())
        let wanted = try await Self.expected(on: scene.rig.programs.active(), after: standing)
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await Self.misses(scene.rig.programs.active()) == wanted)
        #expect(wanted.count == 15 && wanted.values.count(where: { $0 == [4] }) == 3)
        #expect(try await scene.rig.history().count == 1)
    }

    @Test("A deload week writes no miss", arguments: Backing.allCases)
    func finish_deloadWeek_writesNoMisses(backing: Backing) async throws {
        let scene = try await Self.scene(backing, weekIndex: 7)
        #expect(scene.live.isDeload)
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await Self.misses(scene.rig.programs.active()).values.allSatisfy(\.isEmpty))
        #expect(try await scene.rig.history().count == 1)
    }
}
