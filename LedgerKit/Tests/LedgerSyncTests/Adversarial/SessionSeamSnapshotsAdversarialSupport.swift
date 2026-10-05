import Foundation
import LedgerDomain
import LedgerTestSupport

/// A snapshot offered to `start`, and why it must be refused or accepted: `Seam.session(7)` with one edit.
struct SeamSnapshot: Sendable, CustomStringConvertible {
    let description: String
    let state: WorkoutState

    init(_ description: String, _ edit: (inout WorkoutState) -> Void) {
        self.description = description
        var edited = Seam.session(7)
        edit(&edited)
        state = edited
    }

    /// Snapshots the engine ignores a `started` for: ended ones, and live ones that hold a date that is not
    /// finite or a rest outside `0 ... WorkoutEngine.longestRest` (`EventEnvelope.isWellFormed`).
    static let unstartable: [SeamSnapshot] = [
        SeamSnapshot("finished") { $0.phase = .finished },
        SeamSnapshot("discarded") { $0.phase = .discarded },
        SeamSnapshot("finished with an end date") { state in
            state.phase = .finished
            state.endedAt = Seam.at(60)
        },
        SeamSnapshot("started at +infinity") { $0.startedAt = Seam.infinity },
        SeamSnapshot("started at -infinity") { $0.startedAt = Seam.minusInfinity },
        SeamSnapshot("started at NaN") { $0.startedAt = Seam.notANumber },
        SeamSnapshot("live, ended at NaN") { $0.endedAt = Seam.notANumber },
        SeamSnapshot("rest ending at +infinity") { $0.rest = RestTimer(endsAt: Seam.infinity, total: .seconds(60)) },
        SeamSnapshot("rest one attosecond over an hour") {
            $0.rest = RestTimer(endsAt: Seam.at(60), total: WorkoutEngine.longestRest + Duration(attoseconds: 1))
        },
        SeamSnapshot("rest of minus one attosecond") {
            $0.rest = RestTimer(endsAt: Seam.at(60), total: Duration(attoseconds: -1))
        },
        SeamSnapshot("a set done at -infinity") { $0.exercises[4].sets[2].doneAt = Seam.minusInfinity },
        SeamSnapshot("a last performance dated NaN") {
            $0.exercises[2].lastPerformance = LastPerformance(
                date: Seam.notANumber,
                sets: 3,
                reps: 8,
                load: .pounds(70)
            )
        }
    ]

    /// Odd snapshots the engine does start: nothing about them is malformed.
    static let startable: [SeamSnapshot] = [
        SeamSnapshot("no exercises") { state in
            state.exercises = []
            state.cursor = nil
        },
        SeamSnapshot("no cursor") { $0.cursor = nil },
        SeamSnapshot("a cursor that points nowhere") { $0.cursor = Cursor(exerciseIndex: -1, setIndex: 99) },
        SeamSnapshot("live with an end date") { $0.endedAt = Seam.at(5) },
        SeamSnapshot("a rest of exactly an hour") {
            $0.rest = RestTimer(endsAt: Seam.at(3600), total: WorkoutEngine.longestRest)
        },
        SeamSnapshot("a rest of zero that ended long ago") { $0.rest = RestTimer(endsAt: .distantPast, total: .zero) },
        SeamSnapshot("started in the distant future") { $0.startedAt = .distantFuture },
        SeamSnapshot("every set already done") { state in
            for exercise in state.exercises.indices {
                for row in state.exercises[exercise].sets.indices {
                    state.exercises[exercise].sets[row].doneAt = Seam.at(1)
                }
            }
        }
    ]
}
