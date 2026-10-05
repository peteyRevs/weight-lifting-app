import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 11: the contract's seeded scripts of calls made at once, judged as one history
/// (`WorkoutSessionClientContract.concurrentScriptViolation`). They pass on the fake and on the host, over
/// stores that give way inside every call above all, and a client with a fault that shows only when calls
/// overlap breaks them.
///
/// On the host the scripts run `Seeds.hostSeeds` on every set-up: twenty in the PR lane, every seed of the lane
/// in the nightly one (F10 S3 criterion 9). The fake runs every seed of the lane, and every fault runs in both.
@Suite("WorkoutSessionClient · calls made at once, as one history", .tags(.sync), .timeLimit(.minutes(1)))
struct WorkoutSessionConcurrentScriptTests {
    typealias Contract = WorkoutSessionClientContract
    typealias Seeds = WorkoutSessionClientContractTests
    typealias Fault = FaultyWorkoutSession.Fault

    @Test("Calls made at once on the fake are one history", .tags(.property), arguments: Seeds.seeds)
    func fake_isOneHistory(seed: UInt64) async throws {
        let issue = try await Contract.concurrentScriptViolation(seed: seed, on: FakeWorkoutSessionClient())
        #expect(issue == nil, "seed \(seed): \(issue ?? "")")
    }

    @Test(
        "Calls made at once on the host are one history, over every kind of store",
        .tags(.property),
        arguments: Seeds.hostSeeds,
        HostSetup.allCases
    )
    func host_isOneHistory(seed: UInt64, _ setup: HostSetup) async throws {
        let issue = try await Contract.concurrentScriptViolation(seed: seed, on: setup.host())
        #expect(issue == nil, "seed \(seed), \(setup): \(issue ?? "")")
    }

    @Test("The same seed writes the same concurrent script, and another seed another")
    func script_dependsOnItsSeedAlone() {
        let first = Contract.concurrentScript(seed: 7)
        #expect(first.description == Contract.concurrentScript(seed: 7).description)
        #expect(first.description != Contract.concurrentScript(seed: 9).description)
        #expect(first.tasks.map(\.count) == Array(repeating: 6, count: 6))
        // An odd seed has no opening start, so its first task begins with one.
        #expect(first.opening == nil && first.tasks[0][0].description.hasPrefix("start(live"))
        #expect(Contract.concurrentScript(seed: 8).opening?.description.hasPrefix("start(live") == true)
    }

    @Test("Every script holds a start, an end the engine ignores and one it takes, a place apart in three tasks")
    func script_holdsAnIgnoredEndBesideARealOne() {
        for seed in Seeds.fixedSeeds {
            let tasks = Contract.concurrentScript(seed: seed).tasks
            let place = Contract.endsTogether(seed: seed)
            #expect((1 ... 4).contains(place))
            #expect(tasks[0][place - 1].description.hasPrefix("start(live"), "seed \(seed)")
            #expect(tasks[1][place].description == "finish" && tasks[2][place + 1].description == "finish")
        }
    }

    @Test("Twenty concurrent scripts hold every kind of action")
    func scripts_holdEveryKindOfAction() {
        let actions = Seeds.fixedSeeds.flatMap { Contract.concurrentScript(seed: $0).tasks.joined() }
        let kinds = Set(actions.map { String($0.description.prefix { $0 != " " }) })
        #expect(kinds == [
            "start(live", "start(finished", "apply(.setAdded)", "apply(.allSetsRepeated)", "apply(.restStarted)",
            "apply(.started)", "finish", "discard", "updates()"
        ])
    }

    @Test("With no fault the stand-in's calls made at once are one history")
    func noFault_isOneHistory() async throws {
        for seed in Seeds.fixedSeeds {
            #expect(try await Contract.concurrentScriptViolation(seed: seed, on: FaultyWorkoutSession(nil)) == nil)
        }
    }

    /// How many of the twenty fixed seeds must report a fault that needs two calls inside the client at once.
    /// Which call wins is the scheduler's choice, so not every seed can; but a script is written so that most do
    /// (an ignored end beside a real one in every script), and one seed in twenty would rest on the scheduler.
    static let margin = 4

    @Test(
        "A fault that shows only when calls overlap breaks the concurrent script in several of twenty seeds",
        arguments: Fault.allCases.filter(\.needsOverlap)
    )
    func overlapFault_breaksAScript(_ fault: Fault) async throws {
        var reports = 0
        for seed in Seeds.fixedSeeds {
            let issue = try await Contract.concurrentScriptViolation(seed: seed, on: FaultyWorkoutSession(fault))
            reports += issue == nil ? 0 : 1
        }
        #expect(reports >= Self.margin, "\(fault) was reported by \(reports) of \(Seeds.fixedSeeds.count) scripts")
    }

    /// The subscriber that acts on what it is told is the workout screen, and its stream is the second one a
    /// script opens. A client that gets that stream alone wrong, after the subscriber has acted, is seen only
    /// because the stream is read to its end (finding F10-S2-3).
    @Test("A fault on the acting subscriber's stream alone, after it has acted, breaks every script")
    func faultOnTheActingStream_breaksEveryScript() async throws {
        for seed in Seeds.fixedSeeds {
            let faulty = FaultyWorkoutSession(.repeatsAnUpdateOnTheSecondStream)
            let issue = try await Contract.concurrentScriptViolation(seed: seed, on: faulty)
            #expect(issue?.hasPrefix("the acting subscriber's stream") == true, "seed \(seed): \(issue ?? "no issue")")
        }
    }
}
