import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1, criteria 2 and 4 at their edges: what `start`, `finish` and `discard` return,
/// throw and publish on `FakeWorkoutSessionClient`, the order of `start`'s checks, and what is left
/// afterwards. Expected states are the engine's (`Seam.engine`).
@Suite("Adversarial F10 S1 · fake session lifecycle", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeSessionLifecycleAdversarialTests {
    @Test(
        "Criterion 2: a snapshot the engine would not start throws notStartable naming it",
        arguments: SeamSnapshot.unstartable
    )
    func start_unstartableSnapshot_throwsNotStartable_andChangesNothing(_ snapshot: SeamSnapshot) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        #expect(Seam.engine(nil, .started(snapshot.state), in: snapshot.state.id).0 == nil, "the engine starts it")
        #expect(await Seam.outcome(of: .start(snapshot.state), on: fake) == .refused(.notStartable(snapshot.state.id)))
        #expect(await fake.current() == nil)
        #expect(try await Seam.heard(&reader, on: fake) == [Seam.Update(state: nil)])
    }

    @Test(
        "Criterion 2, order of checks: with a workout live, an unstartable snapshot is still notStartable",
        arguments: SeamSnapshot.unstartable
    )
    func start_unstartableSnapshotWhileLive_isNotStartable_notInProgress(_ snapshot: SeamSnapshot) async throws {
        let live = Seam.session(1)
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        #expect(await Seam.outcome(of: .start(snapshot.state), on: fake) == .refused(.notStartable(snapshot.state.id)))
        #expect(await fake.current() == live)
        #expect(try await Seam.heard(&reader, on: fake) == [Seam.Update(state: live)])
    }

    @Test(
        "Criterion 2: an odd snapshot the engine does start becomes current, published once without effects",
        arguments: SeamSnapshot.startable
    )
    func start_oddLiveSnapshot_becomesCurrent(_ snapshot: SeamSnapshot) async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        #expect(Seam.engine(nil, .started(snapshot.state), in: snapshot.state.id).0 == snapshot.state)
        #expect(await Seam.outcome(of: .start(snapshot.state), on: fake) == .returned)
        #expect(await fake.current() == snapshot.state)
        #expect(try await Seam.heard(&reader, on: fake) == [
            Seam.Update(state: nil),
            Seam.Update(state: snapshot.state)
        ])
    }

    @Test("Criterion 2: a second start throws workoutInProgress naming the live workout, whatever it offers")
    func secondStart_throwsWorkoutInProgressNamingTheLiveOne() async throws {
        let live = Seam.session(1)
        var sameIDOtherContent = Seam.session(1, EventBuilders.supersetExercises)
        sameIDOtherContent.name = "Another day under the same id"
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        try await fake.start(live)
        for offered in [Seam.session(2), live, sameIDOtherContent] {
            #expect(await Seam.outcome(of: .start(offered), on: fake) == .refused(.workoutInProgress(live.id)))
            #expect(await fake.current() == live)
        }
        #expect(try await Seam.heard(&reader, on: fake) == [Seam.Update(state: nil), Seam.Update(state: live)])
    }

    @Test(
        "Criterion 2: with nothing live, apply, finish and discard throw noLiveWorkout; apply(.started) starts nothing"
    )
    func nothingLive_everyOtherCallThrowsNoLiveWorkout() async throws {
        let fake = FakeWorkoutSessionClient()
        var reader = await SeamReader(fake)
        let calls: [SeamCall] = [
            .apply(.restSkipped), .apply(.started(Seam.session(1))), .apply(Seam.logged(0, 0, in: 1)),
            .apply(.finished(endedAt: Seam.at(1))), .apply(.discarded(endedAt: Seam.infinity)),
            .finish(Seam.at(1)), .finish(Seam.notANumber), .discard(Seam.at(1)), .discard(Seam.infinity)
        ]
        for call in calls {
            #expect(await Seam.outcome(of: call, on: fake) == .refused(.noLiveWorkout), "\(call)")
            #expect(await fake.current() == nil)
        }
        #expect(try await Seam.heard(&reader, on: fake) == [Seam.Update(state: nil)])
        // `heard` marked the end by starting a workout of its own: the last entry.
        let applied = await fake.applied
        #expect(Seam.sameEvents(Array(applied.dropLast()), calls.map(\.event)))
    }

    @Test("init(live:) is a start nobody asked for: current, first element, applied empty, a second start refused")
    func initLive_isAsIfStarted() async throws {
        let live = Seam.session(3, EventBuilders.supersetExercises, autoRest: false)
        let fake = FakeWorkoutSessionClient(live: live)
        var reader = await SeamReader(fake)
        #expect(await fake.current() == live)
        #expect(await fake.applied.isEmpty)
        #expect(await Seam.outcome(of: .start(Seam.session(4)), on: fake) == .refused(.workoutInProgress(live.id)))
        let logged = try await fake.apply(Seam.logged(0, 0, in: 3))
        #expect(Seam.update(after: Seam.logged(0, 0, in: 3), on: live)?.state == logged)
        #expect(try await Seam.heard(&reader, on: fake) == [
            Seam.Update(state: live),
            Seam.Update(state: logged, effects: [.haptic(.setLogged)])
        ])
    }

    @Test(
        "init(live:) with a snapshot the engine would not start reports an issue and leaves no workout",
        arguments: SeamSnapshot.unstartable
    )
    func initLive_unstartable_reportsAnIssue(_ snapshot: SeamSnapshot) async throws {
        var made: FakeWorkoutSessionClient?
        withKnownIssue {
            made = FakeWorkoutSessionClient(live: snapshot.state)
        }
        let fake = try #require(made)
        #expect(await fake.current() == nil)
        #expect(await Seam.outcome(of: .apply(.restSkipped), on: fake) == .refused(.noLiveWorkout))
        try await fake.start(Seam.session(8))
        #expect(await fake.current() == Seam.session(8))
    }
}
