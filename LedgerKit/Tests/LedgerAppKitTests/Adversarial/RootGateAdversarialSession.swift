import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// One gate and the calls a root makes on it, played one event at a time against `GateModel`. After each event
/// the session waits until the gate has dealt with it (the call returned, or its stream was asked for the next
/// value), so what the gate shows between any two events is read, not guessed.
final class GateSession {
    /// Who is using the app, which decides what the store reports.
    enum Lifter: String, CaseIterable {
        /// Never has a program: the tabs must never show.
        case withoutProgram
        /// Always has one: onboarding must never show.
        case withProgram
        /// Gains and loses one as the play goes.
        case changing
    }

    enum Event: String {
        case start, cancel, passReturnsOpen, passReturnsClosed, report, reportThenCancel, streamEnds
    }

    let gate = RootGate()
    let recorder: GateDestinationRecorder
    let programs = GateScriptedPrograms()
    let lifter: Lifter
    private let program: Program
    private(set) var model = GateModel()
    private(set) var calls: [GateScriptedCall] = []
    /// What was played, for a failing case's message.
    private(set) var played: [String] = []

    init(_ lifter: Lifter) throws {
        self.lifter = lifter
        program = try Fixtures.seedProgram()
        recorder = GateDestinationRecorder(gate)
    }

    private var current: GateScriptedCall? {
        calls.last
    }

    /// The live call's stream, when the call is following and nobody cancelled it.
    private var liveFeed: GateFeed? {
        guard let current, !current.isCancelled, case let .following(index) = current.phase else {
            return nil
        }
        return programs.feed(index)
    }

    /// How many calls have followed a store: the gate must have observed exactly that often.
    var followed: Int {
        calls.count(where: \.hasFollowed)
    }

    /// The events that can happen now.
    var possible: [Event] {
        var events = [Event.start]
        if calls.contains(where: { $0.phase == .launching }) {
            events += [.passReturnsOpen, .passReturnsOpen, .passReturnsClosed]
        }
        if let current, current.phase != .ended, !current.isCancelled {
            events.append(.cancel)
        }
        if liveFeed != nil {
            events += [.report, .report, .report, .reportThenCancel]
            if lifter != .withoutProgram {
                events.append(.streamEnds)
            }
        }
        return events
    }

    func play(_ event: Event, using random: inout GateRandom) async {
        played.append(event.rawValue)
        switch event {
        case .start: await start()
        case .cancel: await cancelCurrent()
        case .passReturnsOpen, .passReturnsClosed:
            let waiting = calls.filter { $0.phase == .launching }
            if let call = waiting.randomElement(using: &random) {
                await returnLaunch(of: call, isOpen: event == .passReturnsOpen)
            }
        case .report:
            switch lifter {
            case .withoutProgram: await report(nil)
            case .withProgram: await report(program)
            case .changing: await report(Bool.random(using: &random) ? program : nil)
            }
        case .streamEnds: await endStream()
        case .reportThenCancel: await reportThenCancel(lifter == .withoutProgram ? nil : program)
        }
    }

    /// The scene's phase changed: SwiftUI cancels the task that is running and starts the next.
    func start() async {
        await cancelCurrent()
        let call = GateScriptedCall()
        calls.append(call)
        await call.start(on: gate)
    }

    func cancelCurrent() async {
        guard let current, current.phase != .ended, !current.isCancelled else {
            return
        }
        current.cancel()
        if current.phase != .launching {
            await current.finished()
            current.phase = .ended
        }
    }

    func returnLaunch(of call: GateScriptedCall, isOpen: Bool) async {
        let index = programs.subscriptions
        call.returnLaunch(isOpen ? programs : nil)
        guard isOpen, !call.isCancelled else {
            await call.finished()
            call.phase = .ended
            return
        }
        call.hasFollowed = true
        await programs.journal.until("subscribe \(index)")
        await programs.feed(index)?.requested(1)
        call.phase = .following(feed: index)
    }

    func returnCurrentLaunch(isOpen: Bool = true) async {
        if let current {
            await returnLaunch(of: current, isOpen: isOpen)
        }
    }

    func report(_ program: Program?) async {
        guard let feed = liveFeed else {
            return
        }
        let asked = feed.requests
        feed.yield(program)
        await feed.requested(asked + 1)
        model.reported(program)
    }

    func reportProgram() async {
        await report(program)
    }

    /// The store reports, and the call is cancelled before its task has run again (the root's task, when the
    /// scene's phase changes in that instant). Round 2: a cancelled call changes nothing, "not even with a
    /// value the store gave before the cancellation and the loop had not yet taken" (`RootGate.follow`).
    func reportThenCancel(_ program: Program?) async {
        guard let feed = liveFeed, let current else {
            return
        }
        feed.yield(program)
        current.cancel()
        await current.finished()
        current.phase = .ended
    }

    /// The stream ends though nobody cancelled its consumer: the active program could not be read.
    func endStream() async {
        guard let feed = liveFeed, let current else {
            return
        }
        feed.finish()
        await current.finished()
        current.phase = .ended
        model.streamEnded()
    }
}

extension GateSession {
    /// Ends the play: every call is cancelled, every launch returns, and every call must return.
    func finish() async {
        for call in calls where call.phase != .ended {
            call.cancel()
        }
        for call in calls where call.phase == .launching {
            call.returnLaunch(programs)
        }
        for call in calls {
            await call.finished()
            call.phase = .ended
        }
    }

    /// Checks the gate against the model and the lifter's rule, after any event.
    func check(_ context: @autoclosure () -> String, sourceLocation: SourceLocation = #_sourceLocation) {
        let shown = gate.destination
        let comment = Comment(rawValue: "\(context()) after \(played.joined(separator: " "))")
        #expect(shown == model.destination, comment, sourceLocation: sourceLocation)
        #expect(programs.subscriptions == followed, comment, sourceLocation: sourceLocation)
        switch lifter {
        case .withoutProgram: #expect(shown != .main, comment, sourceLocation: sourceLocation)
        case .withProgram: #expect(shown != .onboarding, comment, sourceLocation: sourceLocation)
        case .changing: break
        }
    }

    /// Checks the whole play once it has finished: every destination ever held, and what the gate asked of the
    /// launch and of the store.
    func checkWhole(_ context: @autoclosure () -> String, sourceLocation: SourceLocation = #_sourceLocation) {
        let comment = Comment(rawValue: "\(context()) after \(played.joined(separator: " "))")
        #expect(recorder.seen == model.history, comment, sourceLocation: sourceLocation)
        #expect(
            calls.allSatisfy { $0.launches == 1 },
            "each call awaits the launch once",
            sourceLocation: sourceLocation
        )
        let other = programs.journal.entries.filter { !$0.hasPrefix("subscribe") }
        #expect(other.isEmpty, "the gate observes the store and calls nothing else", sourceLocation: sourceLocation)
        switch lifter {
        case .withoutProgram: #expect(!recorder.seen.contains(.main), comment, sourceLocation: sourceLocation)
        case .withProgram: #expect(!recorder.seen.contains(.onboarding), comment, sourceLocation: sourceLocation)
        case .changing: break
        }
    }
}
