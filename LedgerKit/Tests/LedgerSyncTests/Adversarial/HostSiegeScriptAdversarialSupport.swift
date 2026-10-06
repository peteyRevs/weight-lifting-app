import Foundation
import LedgerDomain
import LedgerTestSupport

/// One step of a siege script: a call on the host, or something that happens to it.
enum SiegeStep: Sendable, CustomStringConvertible {
    /// A protocol call. `ignored` says the engine must ignore its event (ADR-004, "Malformed envelopes").
    case call(SeamCall, ignored: Bool)
    /// The app is killed between two store calls and launched again; the launch step runs, or the first
    /// protocol call is left to start recovery.
    case relaunch(recovering: Bool)
    /// `resumeFromStore()` on the host as it runs: a return to the foreground.
    case recover
    /// The system clock moves by this many seconds, forwards or back.
    case clock(TimeInterval)
    /// The store call made `after` calls from now meets `fault`.
    case fault(after: Int, SiegeFault)

    var description: String {
        switch self {
        case let .call(call, ignored): "\(call)\(ignored ? " (ignored)" : "")"
        case let .relaunch(recovering): "relaunch(\(recovering ? "launch step" : "no launch step"))"
        case .recover: "resumeFromStore()"
        case let .clock(seconds): "clock \(seconds) s"
        case let .fault(after, fault): "fault \(fault.rawValue) at store call +\(after)"
        }
    }
}

/// Writes a seeded siege script step by step, told the live workout before each. Every event it writes is one
/// the stores can keep (whole steps of weight, finite dates) and differs from every other, so a stored
/// envelope names the call that made it.
struct SiegeScriptWriter {
    var random: SeamRandom
    private var unique = 0

    init(seed: UInt64) {
        random = SeamRandom(seed: seed)
    }

    mutating func next(live: WorkoutState?) -> SiegeStep {
        switch Int.random(in: 0 ..< 100, using: &random) {
        case 0 ..< 12: .fault(after: Int.random(in: 0 ..< 5, using: &random), fault())
        case 12 ..< 18: .clock(clockMove())
        case 18 ..< 22: .relaunch(recovering: Bool.random(using: &random))
        case 22 ..< 25: .recover
        default: live.map { call(on: $0) } ?? idleCall()
        }
    }

    /// Refusals and lost answers mostly; a death one time in four.
    private mutating func fault() -> SiegeFault {
        let faults: [SiegeFault] = [
            .refuse,
            .refuse,
            .refuse,
            .loseAnswer,
            .loseAnswer,
            .loseAnswer,
            .dieBefore,
            .dieAfter
        ]
        return faults[Int.random(in: 0 ..< faults.count, using: &random)]
    }

    /// A minute or so passes; or the clock repeats, steps back an hour, or jumps a year ahead and back.
    private mutating func clockMove() -> TimeInterval {
        let moves: [TimeInterval] = [0, 7, 45, 90, -3600, -0.0005, 365 * 86400, -365 * 86400]
        return moves[Int.random(in: 0 ..< moves.count, using: &random)]
    }

    private mutating func stamp() -> Double {
        unique += 1
        return Double(unique)
    }

    /// A date no other call carries.
    private mutating func date() -> Date {
        Seam.at(stamp() * 3)
    }

    private mutating func snapshot() -> WorkoutState {
        let number = Int(stamp())
        let shapes = [EventBuilders.seedExercises, EventBuilders.supersetExercises]
        var session = Seam.session(0x51E6E0 + number, shapes[number % 2], autoRest: Bool.random(using: &random))
        session.startedAt = Seam.at(Double(number) * 3)
        return session
    }

    /// With no workout: a start, or now and then a call the protocol refuses.
    private mutating func idleCall() -> SiegeStep {
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0: .call(.apply(.restStarted(endsAt: date(), total: .seconds(60))), ignored: false)
        case 1: .call(.finish(date()), ignored: false)
        case 2: .call(.discard(date()), ignored: false)
        default: .call(.start(snapshot()), ignored: false)
        }
    }

    private mutating func call(on live: WorkoutState) -> SiegeStep {
        switch Int.random(in: 0 ..< 40, using: &random) {
        case 0 ..< 22: .call(.apply(setEvent(live)), ignored: false)
        case 22 ..< 27: .call(.apply(restEvent()), ignored: false)
        case 27 ..< 30: .call(.apply(ignoredEvent(live)), ignored: true)
        case 30 ..< 32: .call(.start(snapshot()), ignored: false)
        case 32 ..< 35: .call(.finish(date()), ignored: false)
        case 35 ..< 37: .call(.discard(date()), ignored: false)
        case 37: .call(.apply(.finished(endedAt: date())), ignored: false)
        case 38: .call(.apply(.discarded(endedAt: date())), ignored: false)
        default: .call(.finish(Seam.infinity), ignored: true)
        }
    }

    /// An edit of one row of the live workout, each with a value of its own.
    private mutating func setEvent(_ live: WorkoutState) -> WorkoutEvent {
        let exerciseIndex = Int.random(in: 0 ..< live.exercises.count, using: &random)
        let sets = live.exercises[exerciseIndex].sets
        let setID = sets[Int.random(in: 0 ..< sets.count, using: &random)].id
        let weight = Weight.pounds(Decimal(stamp()) * 2.5)
        let reps = Reps(clamping: Int.random(in: 1 ... 12, using: &random))
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0 ..< 6:
            return .setLogged(exerciseIndex: exerciseIndex, setID: setID, weight: weight, reps: reps, doneAt: date())
        case 6:
            return .setTargetChanged(exerciseIndex: exerciseIndex, setID: setID, weight: weight, reps: nil)
        case 7:
            let added = LoggedSet(
                id: Seam.freshSet(0x51E6E + Int(stamp())).id,
                weight: weight,
                reps: reps,
                kind: .added
            )
            return .setAdded(exerciseIndex: exerciseIndex, set: added)
        case 8:
            return .allSetsRepeated(exerciseIndex: exerciseIndex, weight: weight, reps: reps)
        default:
            let swapped = ExerciseID(EventBuilders.uuid(0xEE5000 + Int(stamp())))
            return .exerciseSwapped(
                exerciseIndex: exerciseIndex,
                exerciseID: swapped,
                name: "Swap \(unique)",
                alsoUpdateProgram: Bool.random(using: &random)
            )
        }
    }

    private mutating func restEvent() -> WorkoutEvent {
        let tapped = date()
        return switch Int.random(in: 0 ..< 3, using: &random) {
        case 0: .restStarted(endsAt: tapped.addingTimeInterval(90), total: .seconds(90))
        case 1: .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: tapped)
        default: .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: tapped)
        }
    }

    /// What the engine ignores on a live workout: a second `started`, a rest over an hour, a date that is
    /// not finite. Each differs from every event the script stores.
    private mutating func ignoredEvent(_ live: WorkoutState) -> WorkoutEvent {
        var again = live
        again.name = "Started again \(stamp())"
        return switch Int.random(in: 0 ..< 3, using: &random) {
        case 0: .started(again)
        case 1: .restStarted(endsAt: date(), total: WorkoutEngine.longestRest + .seconds(1))
        default: .discarded(endedAt: Seam.notANumber)
        }
    }
}
