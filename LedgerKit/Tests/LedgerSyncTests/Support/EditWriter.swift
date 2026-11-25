import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport

/// Random edits of the live workout, drawn from a seed: logging and unlogging rows, changing their targets,
/// adding rows, moving the cursor, and starting, extending and skipping rests. Each edit is a few seconds after
/// the last, on the hosts' shared clock.
struct EditWriter {
    private var random: SplitMix64
    private var added = 0

    init(seed: UInt64) {
        random = SplitMix64(seed: seed ^ 0x5EED)
    }

    mutating func coin() -> Bool {
        Bool.random(using: &random)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0 ..< 1, using: &random) < probability
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &random)
    }

    /// One random edit on `side`'s live workout, then the host at rest.
    mutating func randomEdit(on side: LiveSyncPair.Side, _ pair: LiveSyncPair) async throws {
        guard let state = try await side.host.current() else {
            return
        }
        pair.clock.set(pair.clock.now.addingTimeInterval(Double(int(in: 1 ... 20))))
        let now = pair.clock.now
        let exercise = int(in: 0 ... state.exercises.count - 1)
        let rows = state.exercises[exercise].sets
        let row = int(in: 0 ... rows.count - 1)
        let id = rows[row].id
        let event: WorkoutEvent = switch int(in: 0 ... 7) {
        case 0, 1:
            .setLogged(exerciseIndex: exercise, setID: id, weight: pounds(), reps: reps(), doneAt: now)
        case 2:
            .setUnlogged(exerciseIndex: exercise, setID: id)
        case 3:
            .setTargetChanged(exerciseIndex: exercise, setID: id, weight: coin() ? pounds() : nil, reps: reps())
        case 4:
            .setAdded(exerciseIndex: exercise, set: newRow(on: side))
        case 5:
            .exerciseSelected(exerciseIndex: exercise, setIndex: row)
        case 6:
            .restStarted(endsAt: now.addingTimeInterval(90), total: .seconds(90))
        default:
            coin() ? .restSkipped : .restExtended(amount: .seconds(30), extendsShownRest: coin(), tappedAt: now)
        }
        try await Self.edit(side, event)
    }

    /// Logs a random row on `side`, a few seconds on.
    mutating func logSet(on side: LiveSyncPair.Side, _ pair: LiveSyncPair) async throws {
        pair.clock.set(pair.clock.now.addingTimeInterval(Double(int(in: 5 ... 60))))
        let exercise = int(in: 0 ... Sample.session.exercises.count - 1)
        let row = int(in: 0 ... Sample.session.exercises[exercise].sets.count - 1)
        let id = Sample.session.exercises[exercise].sets[row].id
        let event = WorkoutEvent.setLogged(
            exerciseIndex: exercise, setID: id, weight: pounds(), reps: reps(), doneAt: pair.clock.now
        )
        try await Self.edit(side, event)
    }

    /// `event` on `side`, then the host at rest, so its frame is on the network.
    static func edit(_ side: LiveSyncPair.Side, _ event: WorkoutEvent) async throws {
        try await side.host.apply(event)
        await side.rest()
    }

    private mutating func pounds() -> Weight {
        .pounds(Decimal(int(in: 9 ... 63) * 5))
    }

    private mutating func reps() -> Reps {
        Reps(clamping: int(in: 1 ... 15))
    }

    private mutating func newRow(on side: LiveSyncPair.Side) -> LoggedSet {
        added += 1
        let device = side.device == EventBuilders.phone ? 0x0A00_0000 : 0x0B00_0000
        return LoggedSet(id: SetID(EventBuilders.uuid(device + added)), weight: pounds(), reps: reps(), kind: .added)
    }
}
