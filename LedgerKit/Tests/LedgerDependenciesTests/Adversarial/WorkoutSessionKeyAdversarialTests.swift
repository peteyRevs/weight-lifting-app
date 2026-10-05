import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1, criterion 6: the `workoutSession` dependency key. Its test value fails the
/// test naming the key; its live value is a stub whose `updates()` ends at once and whose other methods
/// throw `unimplemented(key: "workoutSession")`; its preview value is a fake with no workout, a fresh one
/// for each test.
@Suite("Adversarial F10 S1 · workoutSession key", .timeLimit(.minutes(1)))
struct WorkoutSessionKeyAdversarialTests {
    static let workout = EventBuilders.seedSession()
    static let unimplemented = LedgerDependencyError.unimplemented(key: "workoutSession")

    /// The key's value in `context`.
    static func value(in context: DependencyContext) -> any WorkoutSessionClient {
        withDependencies {
            $0.context = context
        } operation: {
            @Dependency(\.workoutSession) var session
            return session
        }
    }

    /// Every method of `client` but `updates()`, by name.
    static func calls(on client: any WorkoutSessionClient) -> [(String, @Sendable () async throws -> Void)] {
        [
            ("current", { _ = try await client.current() }),
            ("start", { try await client.start(workout) }),
            ("apply", { _ = try await client.apply(.restSkipped) }),
            ("apply(.started)", { _ = try await client.apply(.started(workout)) }),
            ("finish", { _ = try await client.finish(endedAt: EventBuilders.start) }),
            ("discard", { try await client.discard(endedAt: EventBuilders.start) })
        ]
    }

    @Test("Criterion 6: a test that reads the key without configuring it fails, naming the key")
    func testValue_failsTheTestNamingTheKey() {
        withKnownIssue {
            withTestDependencies {
                @Dependency(\.workoutSession) var session
                _ = session
            }
        } matching: { issue in
            issue.description.contains("@Dependency(\\.workoutSession)")
        }
    }

    @Test("Criterion 6: the live value's updates() ends at once, on every call, and before any other call")
    func liveValue_updatesEndsAtOnce() async {
        let stub = Self.value(in: .live)
        for _ in 0 ..< 3 {
            var updates = await stub.updates().makeAsyncIterator()
            #expect(await updates.next() == nil)
            #expect(await updates.next() == nil)
        }
    }

    @Test("Criterion 6: every other method of the live value throws unimplemented naming the key, each time")
    func liveValue_everyOtherMethodThrowsUnimplemented() async {
        let stub = Self.value(in: .live)
        for _ in 0 ..< 2 {
            for (name, call) in Self.calls(on: stub) {
                await #expect(throws: Self.unimplemented, "\(name)") {
                    try await call()
                }
            }
        }
        // A refused start starts nothing: the stub still has no stream to show and still refuses.
        var updates = await stub.updates().makeAsyncIterator()
        #expect(await updates.next() == nil)
    }

    @Test("Criterion 6: the preview value is a fake with no workout that then runs a workout on the real engine")
    func previewValue_isAFakeWithNoWorkout() async throws {
        let preview = Self.value(in: .preview)
        #expect(preview is FakeWorkoutSessionClient)
        #expect(try await preview.current() == nil)
        var updates = await preview.updates().makeAsyncIterator()
        #expect(await updates.next() == WorkoutSessionUpdate(state: nil))
        try await preview.start(Self.workout)
        #expect(await updates.next() == WorkoutSessionUpdate(state: Self.workout))
        let finished = try await preview.finish(endedAt: EventBuilders.start.addingTimeInterval(60))
        #expect(finished.phase == .finished)
        #expect(await updates.next() == WorkoutSessionUpdate(state: finished, haptics: [.workoutFinished]))
        #expect(try await preview.current() == nil)
    }

    /// Starts workout `number` on this test's preview value, which must hold none yet.
    static func startOnThePreviewValue(_ number: Int) async throws {
        let preview = value(in: .preview)
        #expect(try await preview.current() == nil, "test \(number) met another test's workout")
        try await preview.start(EventBuilders.session(
            EventBuilders.seedExercises,
            id: WorkoutID(EventBuilders.uuid(number))
        ))
        #expect(try await preview.current()?.id == WorkoutID(EventBuilders.uuid(number)))
    }

    /// The library keeps one preview value per test function. These three run in any order or at once, and
    /// each starts a workout on its preview value: had they shared a fake, all but one would meet a workout.
    @Test("The preview value of one test never holds the workout another test started (first of three)")
    func previewValue_isNotSharedBetweenTests_first() async throws {
        try await Self.startOnThePreviewValue(1)
    }

    @Test("The preview value of one test never holds the workout another test started (second of three)")
    func previewValue_isNotSharedBetweenTests_second() async throws {
        try await Self.startOnThePreviewValue(2)
    }

    @Test("The preview value of one test never holds the workout another test started (third of three)")
    func previewValue_isNotSharedBetweenTests_third() async throws {
        try await Self.startOnThePreviewValue(3)
    }

    /// Within one test function it is one fake, as it is in one preview process (the key's documentation):
    /// every reader of the key in a preview context meets the workout any of them started. The cases of a
    /// parameterized test are one test function too, and run at once.
    @Test("(documents) within one test the preview value is one fake: two readers of the key share its workout")
    func previewValue_isOneFakeWithinATest() async throws {
        let (one, two) = (Self.value(in: .preview), Self.value(in: .preview))
        try await one.start(Self.workout)
        #expect(try await two.current() == Self.workout)
        #expect(await Self.refusal { try await two.start(Self.workout) } == .workoutInProgress(Self.workout.id))
    }

    /// The `WorkoutSessionError` `call` throws, if it throws one.
    static func refusal(_ call: () async throws -> Void) async -> WorkoutSessionError? {
        do {
            try await call()
            return nil
        } catch {
            return error as? WorkoutSessionError
        }
    }

    @Test("A screen that binds FakeWorkoutSessionClient(live:) for a preview reads that workout from the key")
    func boundFake_isWhatTheKeyReturns() async throws {
        let bound = FakeWorkoutSessionClient(live: Self.workout)
        let current = try await withDependencies {
            $0.context = .preview
            $0.workoutSession = bound
        } operation: {
            @Dependency(\.workoutSession) var session
            return try await session.current()
        }
        #expect(current == Self.workout)
    }
}
