import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// `DatabaseLaunch.run(_:retrying:_:)`: a step the composition root supplies (F10's `resumeWorkout`), run as
/// the launch runs its own. The launch records it, owns its task, and runs it again only when asked.
@MainActor
@Suite("DatabaseLaunch · a composition root's step", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabaseLaunchStepTests {
    struct Refused: Error {}

    @Test("The step is recorded as it begins and run once; it runs again only when retrying")
    func run_recordsTheStep_andRunsItOnce() async {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        var runs = 0
        await subject.launch.run(.resumeWorkout, retrying: false) { runs += 1 }
        await subject.launch.run(.resumeWorkout, retrying: false) { runs += 1 }
        #expect(runs == 1)
        #expect(subject.events == [.began(.resumeWorkout)])
        await subject.launch.run(.resumeWorkout, retrying: true) { runs += 1 }
        #expect(runs == 2)
        #expect(subject.events == [.began(.resumeWorkout), .began(.resumeWorkout)])
    }

    @Test("A step that throws is recorded as failed, once, and is not run again until a call retries")
    func run_failure_isRecorded() async {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        await subject.launch.run(.resumeWorkout, retrying: false) { throw Refused() }
        await subject.launch.run(.resumeWorkout, retrying: false) { throw Refused() }
        #expect(subject.events == [.began(.resumeWorkout), .failed(.resumeWorkout)])
        await subject.launch.run(.resumeWorkout, retrying: true) {}
        #expect(subject.events == [.began(.resumeWorkout), .failed(.resumeWorkout), .began(.resumeWorkout)])
    }

    @Test(
        "The launch owns the step's task: a cancelled caller cancels nothing, and a second call waits for the same run"
    )
    func run_cancelledCaller_neverCancelsTheStep() async {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        let (began, signalBegan) = AsyncStream<Void>.makeStream()
        let (gate, open) = AsyncStream<Void>.makeStream()
        var outcomes: [Bool] = []
        let body: @MainActor () async -> Void = {
            signalBegan.yield()
            for await _ in gate {
                break
            }
            outcomes.append(Task.isCancelled)
        }
        let first = Task { await subject.launch.run(.resumeWorkout, retrying: false, body) }
        for await _ in began {
            break
        }
        first.cancel()
        // Finds the step running: it waits for that run and starts no other, even when retrying.
        let second = Task { await subject.launch.run(.resumeWorkout, retrying: true, body) }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(outcomes.isEmpty)
        open.yield()
        await first.value
        await second.value
        #expect(outcomes == [false])
        #expect(subject.events == [.began(.resumeWorkout)])
    }
}
