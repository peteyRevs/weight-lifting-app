import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criteria 1, 2 and 5 through the host: a swap made with "Also update program"
/// reaches the program when the workout is saved, with the misses, and at no other moment; a discarded workout
/// leaves the program alone. The workout is the seed program's Upper A (`HostMissesAdversarialTests.scene`);
/// expected misses are `MissTracking.update` run here, and the expected exercise is the swap's.
@Suite("Adversarial F10 S3 · a swap reaches the program with the save", .tags(.sync), .timeLimit(.minutes(1)))
struct HostProgramUpdateAdversarialTests {
    typealias Backing = SiegeRig.Backing
    typealias Scenes = HostMissesAdversarialTests

    /// The lat pulldown's row of Upper A, which no scene has logged.
    static let swappedRow = 3

    /// A scene in which the lifter has swapped the fourth exercise for the catalog's last one.
    struct Swapped {
        let scene: SiegeScene
        /// The workout as it stands, the swap in it.
        let standing: WorkoutState
        let slot: SlotID
        let replacement: ExerciseID
        /// The program as it must be stored once the workout is saved: the swap, and the workout's misses.
        let expected: Scenes.Misses
    }

    static func swapped(_ backing: Backing, linked: Bool, alsoUpdateProgram: Bool = true) async throws -> Swapped {
        let scene = try await Scenes.scene(backing, linked: linked)
        let replacement = try #require(try ExerciseCatalog.seed().last)
        let standing = try await scene.host.apply(.exerciseSwapped(
            exerciseIndex: swappedRow, exerciseID: replacement.id, name: replacement.name,
            alsoUpdateProgram: alsoUpdateProgram
        ))
        let slot = try #require(standing.exercises[swappedRow].slotID)
        let misses = try await Scenes.expected(on: scene.rig.programs.active(), after: standing)
        return Swapped(scene: scene, standing: standing, slot: slot, replacement: replacement.id, expected: misses)
    }

    @Test(
        "Finish: the slot takes the swap's exercise, the slots their misses, and nothing else moves",
        arguments: Backing.allCases,
        [true, false]
    )
    func finish_swapUpdatingTheProgram_landsWithTheSave(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked)
        var wanted = try await Self.exercises(swap.scene.rig)
        #expect(wanted[swap.slot] != swap.replacement, "the program still holds the old exercise")
        wanted[swap.slot] = swap.replacement
        _ = try await swap.scene.host.finish(endedAt: SiegeScene.end)
        let issue = try await Self.issue(swap.scene.rig, exercises: wanted, misses: swap.expected)
        #expect(issue == nil, "\(issue ?? "")")
        #expect(try await swap.scene.rig.history().map(\.id) == [swap.standing.id])
    }

    @Test("A swap for this workout only changes no slot's exercise", arguments: Backing.allCases, [true, false])
    func finish_swapNotUpdatingTheProgram_leavesTheExercises(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked, alsoUpdateProgram: false)
        let before = try await Self.exercises(swap.scene.rig)
        _ = try await swap.scene.host.finish(endedAt: SiegeScene.end)
        let issue = try await Self.issue(swap.scene.rig, exercises: before, misses: swap.expected)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test("A discarded workout changes no program, its swap included", arguments: Backing.allCases, [true, false])
    func discard_swapUpdatingTheProgram_changesNoProgram(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked)
        let before = try await swap.scene.rig.programs.active()
        try await swap.scene.host.discard(endedAt: SiegeScene.end)
        let isUntouched = try await swap.scene.rig.programs.active() == before
        #expect(isUntouched, "the program is as it was before the workout")
        #expect(try await swap.scene.rig.history().isEmpty)
    }

    @Test(
        "While a save waits the program is untouched; the retry writes the swap and the misses once",
        arguments: Backing.allCases,
        [true, false]
    )
    func finish_saveFails_theProgramWaitsWithTheWorkout(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked)
        let before = try await swap.scene.rig.programs.active()
        await swap.scene.siege.fail(.materialize, times: 2)
        for _ in 0 ..< 2 {
            #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: swap.scene.host) == "materialize refuse")
            let isUntouched = try await swap.scene.rig.programs.active() == before
            #expect(isUntouched, "no slot of the program has changed")
        }
        _ = try await swap.scene.host.finish(endedAt: SiegeScene.end)
        #expect(try await Self.exercises(swap.scene.rig)[swap.slot] == swap.replacement)
        let issue = try await Self.issue(swap.scene.rig, exercises: nil, misses: swap.expected)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test(
        "A swap to an exercise that is not stored is skipped, and the workout is saved with it",
        arguments: Backing.allCases,
        [true, false]
    )
    func finish_swapToAnExerciseThatIsNotStored_isSkipped(backing: Backing, linked: Bool) async throws {
        let scene = try await Scenes.scene(backing, linked: linked)
        let stranger = ExerciseID(EventBuilders.uuid(0x404))
        try await scene.host.apply(.exerciseSwapped(
            exerciseIndex: Self.swappedRow, exerciseID: stranger, name: "Nobody's lift", alsoUpdateProgram: true
        ))
        let before = try await Self.exercises(scene.rig)
        let finished = try await scene.host.finish(endedAt: SiegeScene.end)
        let issue = try await Self.issue(scene.rig, exercises: before, misses: nil)
        #expect(issue == nil, "\(issue ?? "")")
        #expect(try await scene.rig.history().first?.exercises[Self.swappedRow].exerciseID == stranger)
        #expect(finished.programUpdates.values.contains(stranger))
    }

    @Test(
        "Killed before the save: the relaunch writes the swap to the program as stored then",
        arguments: Backing.allCases,
        [true, false]
    )
    func recovery_killedBeforeTheSave_appliesTheSwap(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked)
        await swap.scene.siege.fail(.materialize, .dieBefore)
        _ = await Seam.outcome(of: .finish(SiegeScene.end), on: swap.scene.host)
        // While the app was dead the lifter's program lost another slot, and one gained misses.
        var program = try #require(try await swap.scene.rig.programs.active())
        program.days[0].slots.remove(at: 4)
        program.days[0].slots[0].misses.formUnion([1, 2])
        try await swap.scene.rig.programs.save(program)
        let finished = try #require(try await swap.scene.rig.replayed(swap.standing.id))
        let relaunched = await swap.scene.rig.host()
        #expect(await SiegeLogs.launch(relaunched) == "no workout")
        #expect(try await Self.exercises(swap.scene.rig)[swap.slot] == swap.replacement)
        let wanted = Scenes.expected(on: program, after: finished)
        let issue = try await Self.issue(swap.scene.rig, exercises: nil, misses: wanted)
        #expect(issue == nil, "\(issue ?? "")")
        #expect(try await swap.scene.rig.programs.active()?.days[0].slots.count == 4, "the removed slot stays removed")
    }

    /// The host writes misses only to the active program (S2 criterion 4); a save writes a swap to the
    /// workout's own program whether or not it is the active one (S3 criterion 1).
    @Test(
        "(documents) Another program active at the finish: no miss is written, and the swap still is",
        arguments: Backing.allCases,
        [true, false]
    )
    func finish_anotherProgramActive_writesTheSwapAndNoMiss(backing: Backing, linked: Bool) async throws {
        let swap = try await Self.swapped(backing, linked: linked)
        let mine = try #require(try await swap.scene.rig.programs.active())
        let other = try Seeders.program(number: 3, exercises: ExerciseCatalog.seed().prefix(6).map(\.id))
        try await swap.scene.rig.programs.save(other)
        _ = try await swap.scene.host.finish(endedAt: SiegeScene.end)
        try await swap.scene.rig.programs.setActive(mine.id)
        let issue = try await Self.issue(swap.scene.rig, exercises: nil, misses: Scenes.misses(mine))
        #expect(issue == nil, "no miss is written: \(issue ?? "")")
        #expect(try await Self.exercises(swap.scene.rig)[swap.slot] == swap.replacement, "the swap")
    }
}

extension HostProgramUpdateAdversarialTests {
    /// `nil` when two maps of slots agree, else how many slots differ: a line, never the maps.
    static func difference<Value: Equatable>(
        _ actual: [SlotID: Value],
        _ expected: [SlotID: Value],
        _ what: String
    ) -> String? {
        let differing = Set(actual.keys).union(expected.keys).filter { actual[$0] != expected[$0] }
        return differing.isEmpty ? nil : "\(what): \(differing.count) of \(expected.count) slots differ"
    }

    /// `nil` when the stored active program holds `exercises` and `misses`, slot by slot.
    static func issue(
        _ rig: SiegeRig,
        exercises: [SlotID: ExerciseID]?,
        misses: Scenes.Misses?
    ) async throws -> String? {
        if let exercises, let line = try await difference(Self.exercises(rig), exercises, "exercises") {
            return line
        }
        guard let misses else {
            return nil
        }
        return try await difference(Scenes.misses(rig.programs.active()), misses, "misses")
    }

    /// The exercise each slot of the stored active program holds.
    static func exercises(_ rig: SiegeRig) async throws -> [SlotID: ExerciseID] {
        let slots = try await rig.programs.active()?.days.flatMap(\.slots) ?? []
        return Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.exerciseID) })
    }
}
