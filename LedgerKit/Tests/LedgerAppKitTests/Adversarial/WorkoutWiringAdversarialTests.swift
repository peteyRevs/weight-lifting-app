import Dependencies
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S2 adversarial round 1, criterion 9: "When the database opens, the iPhone's composition builds the host
/// over the GRDB stores, binds `workoutSession`, and the launch runs the step. A failure is recorded and
/// retried on the next foreground." And criterion 6: the step runs after `loadSettings`, and "a scene-phase
/// task that is cancelled never cancels the step".
@Suite("Adversarial F10 S2 · the app's wiring of the session host", .timeLimit(.minutes(1)))
struct WorkoutWiringAdversarialTests {
    typealias Launch = WorkoutLaunch

    /// The client the composition binds to `workoutSession`.
    static func bound(_ composition: AppComposition) -> any WorkoutSessionClient {
        withDependencies {
            composition.bind(&$0)
        } operation: {
            @Dependency(\.workoutSession) var session
            return session
        }
    }

    @Test("Once the database is open the key is the host, the same one every time, over the opened stores")
    func bind_databaseOpen_bindsTheOneHost() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await AppRun(harness)
        let first = try #require(Self.bound(run.composition) as? LocalWorkoutSessionActor)
        let second = try #require(Self.bound(run.composition) as? LocalWorkoutSessionActor)
        #expect(first === run.session && second === run.session)
        try await first.start(Launch.session)
        #expect(try await run.stores.events.envelopes(for: Launch.session.id).map(\.device) == [run.stores.deviceID])
        #expect(try await Self.bound(run.composition).current() == Launch.session)
    }

    @Test("A composition that is not booted, or whose database cannot be opened, has no host")
    func host_withoutADatabase_isNotBuilt() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let idle = harness.composition()
        await idle.resume(in: .active)
        #expect(idle.session == nil)
        #expect(Launch.steps(harness, .resumeWorkout).isEmpty)
        try FileManager.default.createDirectory(
            at: harness.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not a database, and long enough to be read as one".utf8).write(to: harness.databaseURL)
        let unavailable = harness.booted()
        await unavailable.resume(in: .active)
        #expect(unavailable.state == .databaseUnavailable && unavailable.session == nil)
        #expect(Launch.steps(harness, .resumeWorkout).isEmpty, "no step without a host")
    }

    @Test("A database that opens only on the foreground retry gets its host and its launch step then")
    func host_databaseOpensOnRetry_isBuiltAndRecovers() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Launch.leave(Launch.log(Launch.middle), at: harness.databaseURL)
        let path = harness.databaseURL.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable && composition.session == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        await composition.resume(in: .active)
        let session = try #require(composition.session)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"])
        #expect(try await session.current() == Launch.folded(Launch.middle))
        #expect(Self.bound(composition) as? LocalWorkoutSessionActor === session)
    }

    @Test("The step runs once, after the settings and before WatchConnectivity, and not again while nothing is left")
    func launchStep_cleanLaunch_runsOnceAfterTheSettings() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await AppRun(harness, in: .inactive)
        for phase in [ScenePhase.active, .background, .active, .inactive, .active] {
            await run.composition.resume(in: phase)
        }
        let spelled = LaunchAdversarialTests.spelled(harness.log)
        let order = ["began loadSettings", "began resumeWorkout", "began activateCompanionSession"]
        #expect(spelled.filter(order.contains) == order, "\(spelled)")
        #expect(!spelled.contains { $0.hasPrefix("failed") })
    }

    @Test("A protocol call made before the launch step recovers first, and the step then changes nothing")
    func call_beforeTheLaunchStep_recoversFirst() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Launch.leave(Launch.log(Launch.middle), at: harness.databaseURL)
        let run = try await AppRun(harness, in: nil)
        #expect(Launch.steps(harness, .resumeWorkout).isEmpty)
        let stream = await run.session.updates()
        let expected = try #require(Launch.folded(Launch.middle))
        #expect(try await run.session.current() == expected)
        await run.composition.resume(in: .active)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"])
        let marked = try await run.session.apply(.restSkipped)
        var heard: [WorkoutSessionUpdate] = []
        for await update in stream {
            heard.append(update)
            if update.state == marked {
                break
            }
        }
        #expect(heard.map(\.state) == [expected, marked], "the step published nothing")
    }
}
