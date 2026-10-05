import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1, criterion 3 at its edges: for each kind of event on a live workout, what
/// `apply` returns, whether one update is published, and which effects it carries (the engine's haptics,
/// nothing else). Three classes, by ADR-004: events the engine applies, events it accepts without changing
/// anything (published once all the same: they are part of the log), and events it ignores (never published).
@Suite("Adversarial F10 S1 · fake session updates", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionUpdatesAdversarialTests {
    @Test(
        "Criterion 3: an event the engine applies is returned and published once with its haptics only",
        arguments: SeamEvents.changing
    )
    func apply_changingEvent_isPublishedOnceWithItsHaptics(_ changing: SeamEventCase) async throws {
        let live = Seam.session(1)
        let expected = try await Self.expectPublishedOnce(changing, on: live)
        #expect(expected != live, "the engine leaves the workout as it was: this case belongs in `unchanging`")
    }

    @Test(
        "ADR-004: an event the engine accepts without changing anything is still published once",
        arguments: SeamEvents.unchanging
    )
    func apply_acceptedButUnchangingEvent_isPublishedOnce(_ unchanging: SeamEventCase) async throws {
        let live = Seam.session(1)
        let expected = try await Self.expectPublishedOnce(unchanging, on: live)
        #expect(expected == live, "the engine changes the workout: this case belongs in `changing`")
    }

    /// Applies `accepted` to a fake holding `live` and expects the engine's state back, as `current()`, and
    /// in exactly one update with exactly the case's haptics. Returns the engine's state.
    static func expectPublishedOnce(_ accepted: SeamEventCase, on live: WorkoutState) async throws -> WorkoutState {
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        let (next, effects) = Seam.engine(live, accepted.event, in: live.id)
        let expected = try #require(next)
        #expect(effects.count >= 2, "the engine ignores this event: it belongs in `ignored`")
        #expect(Seam.haptics(effects) == accepted.haptics)

        #expect(await Seam.outcome(of: .apply(accepted.event), on: fake) == .state(expected))
        #expect(await fake.current() == expected)
        #expect(try await Seam.heard(&reader, on: fake) == [
            Seam.Update(state: live),
            Seam.Update(state: expected, effects: accepted.haptics)
        ])
        return expected
    }

    @Test(
        "Criterion 3 and ADR-004: an ignored event returns the workout as it stands and publishes nothing",
        arguments: SeamEvents.ignored
    )
    func apply_ignoredEvent_returnsTheWorkoutUnchanged_publishesNothing(_ ignored: SeamEventCase) async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        #expect(Seam.engine(live, ignored.event, in: live.id).1.isEmpty, "the engine accepts this event")
        #expect(await Seam.outcome(of: .apply(ignored.event), on: fake) == .state(live))
        #expect(await fake.current() == live)
        #expect(try await Seam.heard(&reader, on: fake) == [Seam.Update(state: live)])
        #expect(await fake.applied.count == 2, "applied lists the ignored event and the mark")
    }

    @Test("Criterion 3: logging a done set again buzzes again; un-logging and re-logging buzz as the engine says")
    func apply_relogUnlogRelog_carriesTheEnginesHaptics() async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        let events: [WorkoutEvent] = [
            Seam.logged(0, 0, in: 1, at: 10), Seam.logged(0, 0, in: 1, at: 20),
            .setUnlogged(exerciseIndex: 0, setID: Seam.setID(0, 0, in: 1)), Seam.logged(0, 0, in: 1, at: 30)
        ]
        var state = live
        var expected = [Seam.Update(state: live)]
        for event in events {
            let update = try #require(Seam.update(after: event, on: state))
            state = try #require(update.state)
            expected.append(update)
            #expect(try await fake.apply(event) == state)
        }
        #expect(expected.map(\.effects.count) == [0, 1, 1, 0, 1])
        #expect(try await Seam.heard(&reader, on: fake) == expected)
    }

    @Test("Criterion 3: the last set of a superset round starts the group rest; the update carries no rest effect")
    func apply_supersetRound_forwardsOnlyTheHaptic() async throws {
        let live = Seam.session(5, EventBuilders.supersetExercises)
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        let afterA = try await fake.apply(Seam.logged(0, 0, in: 5, at: 40))
        let afterB = try await fake.apply(Seam.logged(1, 0, in: 5, at: 80))
        #expect(afterA.rest == nil && afterA.cursor == Cursor(exerciseIndex: 1, setIndex: 0))
        #expect(afterB.rest == RestTimer(endsAt: Seam.at(170), total: .seconds(90)))
        #expect(afterB.cursor == Cursor(exerciseIndex: 0, setIndex: 1))
        #expect(try await Seam.heard(&reader, on: fake) == [
            Seam.Update(state: live),
            Seam.Update(state: afterA, effects: [.haptic(.setLogged)]),
            Seam.Update(state: afterB, effects: [.haptic(.setLogged)])
        ])
    }
}
