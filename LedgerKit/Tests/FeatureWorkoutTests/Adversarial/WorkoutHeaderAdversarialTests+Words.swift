@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// The header's words and the screen's states.
extension WorkoutHeaderAdversarialTests {
    @Test("An added set widens its exercise's segment")
    func segments_addedSetWidens() async throws {
        let state = EventBuilders.session(specs([3, 3]))
        let session = FakeWorkoutSessionClient(live: state)
        let last = try #require(state.exercises[1].sets.last)
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xABC)),
            weight: last.weight,
            reps: last.reps,
            kind: last.kind
        )
        let next = try await session.apply(.setAdded(exerciseIndex: 1, set: added))
        #expect(picture(next) == "3c 4u")
    }

    @Test("The header's words, its start and its busy state")
    func header_words() {
        var state = EventBuilders.session(specs([3]))
        state.name = "Lower B — Hinge focus"
        let header = WorkoutPresentation.header(state, isBusy: true, locale: Fixtures.locale)
        #expect(header.minimize == "Minimize")
        #expect(header.finish == "Finish")
        #expect(header.title == "Lower B — Hinge focus")
        #expect(header.startedAt == state.startedAt)
        #expect(header.elapsedLabel == "Elapsed time")
        #expect(header.elapsedLabel.allSatisfy { !$0.isNumber }, "criterion 6: VoiceOver's label carries no time")
        #expect(!header.isEnabled)
        #expect(WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale).isEnabled)
    }

    @Test("The screen's three states")
    func screen_states() {
        let state = EventBuilders.session(specs([3]))
        #expect(WorkoutPresentation.screen(.idle, isBusy: false, locale: Fixtures.locale) == .loading)
        #expect(WorkoutPresentation.screen(.loading, isBusy: false, locale: Fixtures.locale) == .loading)
        let loaded = WorkoutPresentation.screen(.loaded(state), isBusy: false, locale: Fixtures.locale)
        #expect(loaded.drawnHeader?.title == state.name)
        guard case let .failed(failed) = WorkoutPresentation.screen(
            .failed(WorkoutStoreError.updatesEnded),
            isBusy: false,
            locale: Fixtures.locale
        ) else {
            Issue.record("a failed load is not drawn as failed")
            return
        }
        let words = "\(failed.title) / \(failed.message) / \(failed.close)"
        #expect(words == "Couldn't open this workout / Close this screen and try again. / Close")
    }
}
