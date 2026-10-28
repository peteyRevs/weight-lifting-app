import Dependencies
@testable import FeatureLibrary
import Foundation
#if os(iOS)
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import UIKit
#endif
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3 adversarial round (G2): the exercise sheet's store where its own tests are silent. An edit of a stored
/// exercise whose secondary muscles hold its primary one (S3-5); Save's problem never reaching VoiceOver (S3-6); and
/// pins of Q5 A (a renamed exercise that is already logged: the Library follows the id, past workouts keep the name
/// they were logged under), of an edit that only changes the case of its own name, and of an edit to another's name.
/// Secondary chips identified by place (S3-7).
@MainActor
@Suite("Adversarial F12 S3 · CreateExerciseStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct CreateExerciseAdversarialTests {
    static let custom = LibraryFixtures.custom

    // MARK: S3-5

    @Test("S3-5. Editing a stored exercise whose secondary muscles hold its primary one can be saved")
    func edit_primaryAmongStoredSecondaries_canBeSaved() async {
        var stored = Self.custom
        stored.secondaryMuscles = [.chest, .triceps] // its primary, chest, among them: a row this sheet never wrote
        let scene = CreateScene(editing: stored)
        #expect(!scene.store.model.groups[2].chips.map(\.title).contains("Chest"), "the sheet shows no chip to clear")
        scene.store.send(.setName("Landmine Squeeze Press Wide"))
        scene.store.send(.save)
        await scene.store.save()
        // S3-5, fixed in S3 fix round 1: the draft of a stored exercise takes its primary out of the secondaries.
        #expect(scene.store.phase == .saved)
        #expect(scene.store.model.foot.problem == nil)
    }

    // MARK: S3-6

    #if os(iOS)
        /// What VoiceOver was told by the hosted sheet.
        @MainActor @Observable
        final class Heard {
            var announcements: [String] = []
        }

        /// S3-6, fixed in S3 fix round 1. The orchestrator ruled that G2's source check be replaced by this behavioural
        /// test: the sheet hosted in a window runs its save from its own task and announces what Save found, each
        /// time, the same line again too, and a failed save's line over Save.
        @Test("S3-6. The problem Save finds is announced to VoiceOver, as Program's and Onboarding's notices are")
        func saveProblem_isAnnounced() async {
            let scene = CreateScene(failures: 1)
            let heard = Heard()
            let sheet = CreateExerciseSheet(
                store: scene.store,
                onClose: {},
                announce: { heard.announcements.append($0) }
            )
            let host = UIHostingController(rootView: sheet)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            scene.store.send(.save)
            await eventually { heard.announcements.count == 1 }
            scene.store.send(.save)
            await eventually { heard.announcements.count == 2 }
            scene.store.send(.setName("Landmine Squeeze Press 2"))
            scene.store.send(.save)
            await eventually { heard.announcements.count == 3 }
            #expect(heard.announcements == [
                "Enter a name.", "Enter a name.", "Couldn't save the exercise. Try again."
            ])
        }
    #endif

    // MARK: S3-7

    @Test("S3-7. A secondary muscle's chip keeps its identity when the primary muscle changes")
    func secondaryChipIdentity_isTheMuscle() {
        let scene = CreateScene()
        let ids = { (title: String) in scene.store.model.groups[2].chips.first { $0.title == title }?.id }
        let shoulders = ids("Shoulders")
        scene.store.send(.setPrimaryMuscle(.triceps))
        // S3-7, fixed in S3 fix round 1: a chip is identified by its value.
        #expect(ids("Shoulders") == shoulders)
        #expect(scene.store.model.groups[2].chips.first?.title == "Chest", "place 0 was Back, is now Chest")
    }

    // MARK: Pins

    @Test("Pin (Q5 A): a logged exercise renamed: the Library shows the new name, past workouts keep the old")
    func rename_ofALoggedExercise_followsTheID() async throws {
        let scene = LibraryScene(
            catalog: LibraryFixtures.catalog + [Self.custom],
            workouts: LibraryFixtures.sessions(of: Self.custom, 2, pounds: 95, reps: 8)
        )
        let run = await scene.running()
        defer { run.cancel() }
        await eventually { (try? scene.model.names(.recent)) == [Self.custom.name] }
        let store = withTestDependencies {
            $0.exerciseRepository = scene.memory.exercises
            $0.uuid = .incrementing
        } operation: {
            CreateExerciseStore(editing: Self.custom)
        }
        store.send(.setName("Landmine Squeeze Wide"))
        store.send(.setEquipment(.dumbbell))
        store.send(.save)
        await store.save()
        #expect(store.phase == .saved)
        await eventually { (try? scene.model.names(.recent)) == ["Landmine Squeeze Wide"] }
        let meta = try scene.model.row("Landmine Squeeze Wide", in: .recent)?.meta
        #expect(meta == "Dumbbell · Chest · 2 sessions · Custom", "\(meta ?? "nil")")
        #expect(try scene.model.row("Landmine Squeeze Wide")?.record == "95")
        let logged = try await scene.memory.workouts.recent(limit: 10).flatMap(\.exercises)
        let keepsTheirName = logged.count == 2 && logged.allSatisfy { $0.name == Self.custom.name }
        #expect(keepsTheirName, "\(logged.map(\.name))")
        let stored = try #require(try await scene.memory.exercises.exercise(id: Self.custom.id))
        #expect(stored.name == "Landmine Squeeze Wide" && stored.shortName == "Landmine Squeeze Wide" && stored
            .isCustom)
    }

    @Test("Pin: an edit may change only the case of its own name; to another exercise's name it may not")
    func edit_ownNameAndAnothers() async throws {
        let scene = CreateScene(editing: Self.custom)
        try await scene.memory.exercises.save(Self.custom)
        scene.store.send(.setName("Barbell Bench Press"))
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.model.name.problem == "An exercise with that name already exists.")
        scene.store.send(.setName("  LANDMINE squeeze PRESS "))
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .saved)
        #expect(scene.exercises.saves.map(\.id) == [Self.custom.id])
        #expect(try await scene.stored("LANDMINE squeeze PRESS")?.id == Self.custom.id)
    }

    @Test("Pin: a primary muscle chosen after the secondaries leaves the others and takes itself out")
    func primaryChangedAfterSecondaries() {
        let scene = CreateScene()
        for muscle in [MuscleGroup.back, .biceps, .core] {
            scene.store.send(.setSecondaryMuscle(muscle, isOn: true))
        }
        scene.store.send(.setPrimaryMuscle(.biceps))
        scene.store.send(.setSecondaryMuscle(.biceps, isOn: true))
        #expect(scene.store.draft.secondaryMuscles == [.back, .core])
        scene.store.send(.setPrimaryMuscle(.chest))
        #expect(scene.store.draft.secondaryMuscles == [.back, .core], "the old primary does not come back by itself")
        let secondary = scene.store.model.groups[2]
        #expect(secondary.chips.filter(\.isSelected).map(\.title) == ["Back", "Core"])
        #expect(!secondary.chips.map(\.title).contains("Chest"))
    }
}
