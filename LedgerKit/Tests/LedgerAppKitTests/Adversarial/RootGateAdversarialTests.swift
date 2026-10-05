import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S3 adversarial round 1 (G2), criteria 1 to 4: the gate alone, against the specification as a model, over a
/// launch and a store the test moves one event at a time. The root draws `destination` and nothing else of the
/// gate, so a destination the gate never held is a screen the root never showed.
@Suite("Adversarial F08 S3 · the gate against a model", .timeLimit(.minutes(1)))
struct RootGateAdversarialTests {
    typealias Lifter = GateSession.Lifter

    /// Seeds 0 ..< 300, a third for each lifter; a failing case prints its seed and the events it played.
    @Test(
        "Seeded random orders of the pass, the answers, a stream's end and cancelled calls match the model",
        arguments: 0 ..< 300
    )
    func randomOrders_matchTheModel(seed: Int) async throws {
        var random = GateRandom(seed: UInt64(seed))
        let lifter = Lifter.allCases[seed % Lifter.allCases.count]
        let session = try GateSession(lifter)
        for step in 0 ..< 30 {
            guard let event = session.possible.randomElement(using: &random) else {
                break
            }
            await session.play(event, using: &random)
            session.check("seed \(seed) \(lifter.rawValue) step \(step)")
        }
        await session.finish()
        session.check("seed \(seed) \(lifter.rawValue), finished")
        session.checkWhole("seed \(seed) \(lifter.rawValue)")
    }

    @Test(
        "While the launch's pass runs the gate decides nothing and reads nothing, whoever the lifter is",
        arguments: Lifter.allCases
    )
    func passRunning_decidesNothing(_ lifter: Lifter) async throws {
        let session = try GateSession(lifter)
        await session.start()
        session.check("the pass is running")
        #expect(session.gate.destination == .loading)
        #expect(session.programs.subscriptions == 0, "the store is read before the pass has returned")
        await session.finish()
        session.checkWhole("never answered")
        #expect(session.recorder.seen == [.loading])
    }

    @Test("Between the pass returning and the store's first answer the gate still shows nothing")
    func firstAnswerPending_decidesNothing() async throws {
        let session = try GateSession(.changing)
        await session.start()
        await session.returnCurrentLaunch()
        #expect(session.gate.destination == .loading)
        #expect(session.programs.subscriptions == 1, "one read of the active program")
        await session.report(nil)
        #expect(session.gate.destination == .onboarding)
        await session.finish()
        session.checkWhole("first answer")
    }

    @Test("A lifter without a program goes from nothing to onboarding and never sees the tabs, through phase changes")
    func noProgram_neverShowsTheTabs() async throws {
        let session = try GateSession(.withoutProgram)
        await session.start() // launched in the background
        await session.start() // the phase changes while the pass runs: a second call, the first cancelled
        await session.start()
        for call in session.calls.reversed() { // the newest call's pass returns first
            await session.returnLaunch(of: call, isOpen: true)
            session.check("a pass returned")
        }
        #expect(session.gate.destination == .loading, "the store has not answered")
        await session.report(nil)
        #expect(session.gate.destination == .onboarding)
        await session.start() // the scene goes to the background, mid-onboarding
        #expect(session.gate.destination == .onboarding, "the screen keeps its place while the next call starts")
        await session.returnCurrentLaunch()
        #expect(session.gate.destination == .onboarding)
        await session.report(nil)
        await session.finish()
        session.checkWhole("no program")
        #expect(session.recorder.seen == [.loading, .onboarding])
    }

    @Test("A lifter with a program goes from nothing to the tabs and never sees onboarding, even when a read fails")
    func program_neverShowsOnboarding() async throws {
        let session = try GateSession(.withProgram)
        await session.start()
        await session.start()
        await session.returnLaunch(of: session.calls[0], isOpen: true) // the cancelled call's pass
        #expect(session.gate.destination == .loading)
        await session.returnCurrentLaunch()
        await session.reportProgram()
        #expect(session.gate.destination == .main)
        await session.endStream() // the program cannot be read any more
        #expect(session.gate.destination == .main)
        await session.start()
        await session.returnCurrentLaunch()
        await session.endStream() // nor on the next foreground, before any value
        await session.finish()
        session.checkWhole("program")
        #expect(session.recorder.seen == [.loading, .main])
    }

    @Test("A stream that ends on a task nobody cancelled shows the tabs, never onboarding, from any screen")
    func streamEnds_showsTheTabs() async throws {
        for before in [RootGate.Destination.loading, .onboarding, .main] {
            let session = try GateSession(.changing)
            await session.start()
            await session.returnCurrentLaunch()
            if before == .onboarding {
                await session.report(nil)
            }
            if before == .main {
                await session.reportProgram()
            }
            #expect(session.gate.destination == before)
            await session.endStream()
            #expect(session.gate.destination == .main, "from \(before)")
            await session.finish()
            session.checkWhole("ended from \(before)")
        }
    }

    @Test("A stream that ends because its call was cancelled changes nothing, from any screen")
    func streamEndsByCancellation_changesNothing() async throws {
        for before in [RootGate.Destination.loading, .onboarding, .main] {
            let session = try GateSession(.changing)
            await session.start()
            await session.returnCurrentLaunch()
            if before == .onboarding {
                await session.report(nil)
            }
            if before == .main {
                await session.reportProgram()
            }
            await session.cancelCurrent()
            #expect(session.gate.destination == before, "from \(before)")
            #expect(session.recorder.seen.last == before)
            await session.finish()
            session.checkWhole("cancelled from \(before)")
        }
    }

    @Test("A database that is not open decides nothing; the call after it opens is followed")
    func databaseNotOpen_decidesNothing_thenFollows() async throws {
        let session = try GateSession(.withoutProgram)
        await session.start()
        await session.returnCurrentLaunch(isOpen: false)
        #expect(session.gate.destination == .loading)
        #expect(session.programs.subscriptions == 0)
        await session.start() // the next foreground: the database opens (product decision #29)
        await session.returnCurrentLaunch()
        await session.report(nil)
        #expect(session.gate.destination == .onboarding)
        await session.finish()
        session.checkWhole("opened late")
    }
}
