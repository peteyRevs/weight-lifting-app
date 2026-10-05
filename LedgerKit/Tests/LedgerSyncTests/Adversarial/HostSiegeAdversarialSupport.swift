import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// The system clock a host under test reads, set by the test (F10 S2 adversarial round 1).
final class SiegeClock: Sendable {
    private let reading: Mutex<Date>

    init(_ date: Date = EventBuilders.start) {
        reading = Mutex(date)
    }

    var now: Date {
        reading.withLock { $0 }
    }

    func set(_ date: Date) {
        reading.withLock { $0 = date }
    }

    func advance(_ seconds: TimeInterval) {
        reading.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// A store call a session host makes.
enum SiegeCall: String, Sendable, CaseIterable {
    case append, envelopes, unreadableCount, highestSeq, uncompactedWorkoutIDs, newestWallClock, compact
    case materialize, activeProgram
}

/// What a store call can be made to do in place of answering.
enum SiegeFault: String, Sendable, Equatable {
    /// It throws before it reaches the store.
    case refuse
    /// The store does what was asked, and the call throws all the same: the answer is lost.
    case loseAnswer
    /// The process dies before the store is reached: this call and every later one of this host throw.
    case dieBefore
    /// The process dies once the store has done what was asked.
    case dieAfter
}

/// What a faulted store call throws.
struct SiegeError: Error, Equatable, Sendable {
    let call: SiegeCall
    let fault: SiegeFault
}

/// What every store call of a dead host throws: the process is gone, and its stores with it.
struct SiegeDead: Error, Equatable, Sendable {}

/// A fault that waits for the calls of one kind: `times` of them, once `skipping` have passed.
struct Standing: Sendable {
    let fault: SiegeFault
    var times: Int
    var skipping: Int
}

/// The test's hand on a host's three stores. Every call the host makes goes through it: it is counted, can be
/// made to fail (by kind, or the n-th call whatever its kind), to wait, or to kill the host, and what reached
/// the stores is recorded for good, compaction or not. Written from `WorkoutEventStore`'s, `WorkoutRepository`'s
/// and `ProgramRepository`'s documentation; it shares nothing with `StoreProbe`.
actor Siege {
    private(set) var calls: [SiegeCall] = []
    /// Every envelope the event store newly took, in the order it took them.
    private(set) var stored: [EventEnvelope] = []
    /// Every workout a `materialize` wrote, with its slot updates, in order.
    private(set) var saved: [(workout: WorkoutState, slots: [Slot])] = []
    /// Every log a `compact` dropped, in order.
    private(set) var dropped: [WorkoutID] = []
    /// How many faults have fired.
    private(set) var fired = 0
    /// The host generation whose calls reach the stores: a new host, or a death, retires the one before.
    private(set) var generation = 0
    private(set) var hasDied = false
    private var numbered: [Int: SiegeFault] = [:]
    private var standing: [SiegeCall: Standing] = [:]
    private var held: SiegeCall?
    private var parked: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    /// The next `times` calls of `call` meet `fault`, once `skipping` of them have passed.
    func fail(_ call: SiegeCall, _ fault: SiegeFault = .refuse, times: Int = 1, skipping: Int = 0) {
        standing[call] = Standing(fault: fault, times: times, skipping: skipping)
    }

    /// The store call numbered `index` (the first is 0), whatever its kind, meets `fault`.
    func failCall(numbered index: Int, _ fault: SiegeFault) {
        numbered[index] = fault
    }

    /// No call fails any more.
    func heal() {
        numbered = [:]
        standing = [:]
    }

    var hasFaultsWaiting: Bool {
        !numbered.isEmpty || !standing.isEmpty
    }

    func forgetCalls() {
        calls = []
    }

    /// A new host is about to be built: every host before it is dead to the stores.
    func nextGeneration() -> Int {
        generation += 1
        hasDied = false
        return generation
    }

    /// The next `call` waits inside the store until `release()`.
    func hold(_ call: SiegeCall) {
        held = call
    }

    /// Returns once a held call is waiting.
    func waitUntilHeld() async {
        if parked == nil {
            await withCheckedContinuation { arrivals.append($0) }
        }
    }

    func release() {
        parked?.resume()
        parked = nil
    }

    func took(_ envelopes: [EventEnvelope]) {
        stored += envelopes
    }

    func wrote(_ workout: WorkoutState, _ slots: [Slot]) {
        saved.append((workout, slots))
    }

    func compacted(_ workout: WorkoutID) {
        dropped.append(workout)
    }

    /// Before the store: counts the call, parks it when held, and throws when it must not reach the store.
    func enter(_ call: SiegeCall, _ host: Int) async throws -> SiegeFault? {
        guard host == generation else {
            throw SiegeDead()
        }
        let index = calls.count
        calls.append(call)
        if held == call {
            held = nil
            await withCheckedContinuation { continuation in
                parked = continuation
                arrivals.forEach { $0.resume() }
                arrivals = []
            }
        }
        guard host == generation else {
            throw SiegeDead()
        }
        let fault = numbered.removeValue(forKey: index) ?? nextStanding(call)
        switch fault {
        case .refuse:
            fired += 1
            throw SiegeError(call: call, fault: .refuse)
        case .dieBefore:
            die()
            throw SiegeDead()
        case .loseAnswer, .dieAfter, nil:
            return fault
        }
    }

    /// After the store did what was asked: throws when the answer is lost or the process died.
    func leave(_ call: SiegeCall, _ fault: SiegeFault?) throws {
        switch fault {
        case .loseAnswer:
            fired += 1
            throw SiegeError(call: call, fault: .loseAnswer)
        case .dieAfter:
            die()
            throw SiegeDead()
        case .refuse, .dieBefore, nil:
            return
        }
    }

    private func die() {
        fired += 1
        generation += 1
        hasDied = true
    }

    private func nextStanding(_ call: SiegeCall) -> SiegeFault? {
        guard var fault = standing[call] else {
            return nil
        }
        guard fault.skipping == 0 else {
            fault.skipping -= 1
            standing[call] = fault
            return nil
        }
        fault.times -= 1
        standing[call] = fault.times > 0 ? fault : nil
        return fault.fault
    }
}
