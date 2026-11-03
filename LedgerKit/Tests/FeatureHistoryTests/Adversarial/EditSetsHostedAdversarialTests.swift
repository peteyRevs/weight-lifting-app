#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureHistory
    import LedgerDependencies
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S3 adversarial (G2), through the hosted sheet and VoiceOver's own actions: "Cancel" on a live sheet and on
    /// one saving, the app's own init, a failure said each time, and adjustable steppers reaching the draft.
    @MainActor
    @Suite("Adversarial F13 S3 · the sheet hosted", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct EditSetsHostedAdversarialTests {
        @MainActor @Observable
        final class Told {
            var closes: [EditSetsClosing] = []
            var announced: [String] = []
        }

        private static func sheet(_ store: EditSetsStore, _ told: Told) -> EditSetsSheet {
            EditSetsSheet(store: store) { told.closes.append($0) } announce: { told.announced.append($0) }
        }

        private static func label(_ element: NSObject) -> String {
            element.accessibilityLabel ?? ""
        }

        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        @Test("Cancel on an edited sheet closes it, not gone, and stores nothing")
        func cancel_closes_andStoresNothing() async throws {
            let scene = EditScene()
            let told = Told()
            try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
            Self.sheet(scene.store, told).withAccessibilityElements(outsideScrollViews: true) { elements in
                let cancel = elements.first { Self.label($0) == "Cancel" }
                #expect(cancel?.accessibilityActivate() == true)
            }
            #expect(told.closes == [.cancelled])
            #expect(scene.workouts.saveCount == 0)
            #expect(try await scene.memory.workouts.workout(id: scene.workout.id) == scene.workout)
        }

        @Test("While a save runs, Cancel is refused however it is reached")
        func cancel_whileSaving_isRefused() throws {
            let scene = EditScene()
            let told = Told()
            try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
            scene.store.send(.save)
            Self.sheet(scene.store, told).withAccessibilityElements(outsideScrollViews: true) { elements in
                let cancel = elements.first { Self.label($0) == "Cancel" }
                _ = cancel?.accessibilityActivate()
                _ = cancel?.accessibilityPerformEscape()
            }
            #expect(told.closes.isEmpty)
        }

        @Test("The app's own init makes a store of the request that draws its sets")
        func appsInit_drawsTheRequest() {
            let workout = HistoryFixtures.twelve()[11]
            let closes = LockIsolatedCloses()
            let sheet = withTestDependencies {
                $0.workoutRepository = InMemoryStores().workouts
            } operation: {
                EditSetsSheet(request: EditSetsRequest(workout: workout, units: .lb)) { closes.append($0) }
            }
            let labels = sheet.withAccessibilityElements(outsideScrollViews: true) { $0.map(Self.label) }
            #expect(labels.contains("Edit sets"))
            #expect(labels.contains("Save"))
            #expect(closes.values.isEmpty)
        }

        @Test("N12. A failure is announced each time, not only the first")
        func failure_isAnnouncedEachTime() async throws {
            let stores = InMemoryStores(seed: InMemoryStores.Seed(
                workouts: [HistoryFixtures.twelve()[11]],
                settings: Fixtures.settingsLb
            ))
            let seen = ScriptedWorkouts(base: stores.workouts, scripted: false, failures: 2)
            let workout = HistoryFixtures.twelve()[11]
            let store = withTestDependencies {
                $0.workoutRepository = seen
            } operation: {
                EditSetsStore(EditSetsRequest(workout: workout, units: .lb))
            }
            let told = Told()
            try await Self.hosting(Self.sheet(store, told)) {
                let set = try #require(workout.exercises.first?.sets.first)
                store.send(.step(set.id, .weight, .upward))
                store.send(.save)
                await eventually { told.announced.count == 1 }
                store.send(.save)
                await eventually { told.announced.count == 2 }
                #expect(seen.saveCount == 2)
                store.send(.save)
                await eventually { told.closes == [.saved(store.draft)] }
                #expect(told.announced.count == 2)
                #expect(seen.saveCount == 3)
            }
        }

        @Test(
            "N15. VoiceOver's swipes reach the draft: up and down on each stepper, not at its limit, not when disabled"
        )
        func adjustable_reachesTheDraft() {
            var workout = HistoryFixtures.twelve()[11]
            workout.exercises[0].sets[0].reps = .one
            let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: [workout], settings: Fixtures.settingsLb))
            let store = withTestDependencies {
                $0.workoutRepository = stores.workouts
            } operation: {
                EditSetsStore(EditSetsRequest(workout: workout, units: .lb))
            }
            let set = workout.exercises[0].sets[0]
            let draftSet = { store.draft.exercises[0].sets[0] }
            EditSetsPage(model: store.model, send: store.send).withAccessibilityElements { elements in
                let weight = elements.first { Self.label($0) == "Set 1 weight" }
                let reps = elements.first { Self.label($0) == "Set 1 reps" }
                reps?.accessibilityDecrement()
                #expect(draftSet().reps == .one, "a swipe towards the limit changes nothing")
                weight?.accessibilityIncrement()
                #expect(draftSet().weight > set.weight)
            }
            let moved = draftSet()
            EditSetsPage(model: store.model, send: store.send).disabled(true).withAccessibilityElements { elements in
                let weight = elements.first { Self.label($0) == "Set 1 weight" }
                weight?.accessibilityIncrement()
                #expect(draftSet() == moved, "a disabled sheet takes no swipe")
            }
        }
    }

    extension EditSetsHostedAdversarialTests {
        @Test("Save on the foot sends its action once it has one, and nothing while it is off")
        func save_sendsOnlyItsAction() throws {
            for preview in [EditPreview.unchanged, .changed] {
                let model = try preview.model()
                var sent: [EditSetsAction] = []
                EditSetsFoot(model: model.foot) { sent.append($0) }.withAccessibilityElements { elements in
                    _ = elements.first { Self.label($0) == "Save" }?.accessibilityActivate()
                }
                #expect(sent == (model.foot.action.map { [$0] } ?? []), "\(preview)")
            }
        }

        @Test("N15. An exercise with nothing logged is read: its heading, then \"Nothing logged\", and no stepper")
        func nothingLogged_isRead() {
            let workout = EditFixtures.partlyLogged()
            let model = EditSetsPresentation.make(EditSetsInput(
                draft: workout,
                units: .lb,
                locale: Fixtures.locale,
                hasChanges: false,
                isSaving: false,
                saveFailed: false,
                workoutGone: false
            ))
            let labels = EditSetsPage(model: model) { _ in }.withAccessibilityElements { $0.map(Self.label) }
            let name = workout.exercises[1].name
            let place = labels.firstIndex(of: name)
            let next = place.flatMap { labels.indices.contains($0 + 1) ? labels[$0 + 1] : nil }
            #expect(next == "Nothing logged", "\(labels)")
            #expect(labels.last == "Nothing logged", "no stepper under it")
            #expect(EditSetsRequest(workout: workout, units: .kg).id == workout.id, "the sheet is the workout's")
        }
    }

    /// What the app's own init's closure was told, for a test outside the main actor's closure type.
    private final class LockIsolatedCloses {
        var values: [EditSetsClosing] = []

        func append(_ value: EditSetsClosing) {
            values.append(value)
        }
    }
#endif
