@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S5 criteria 3 and 6: a workout walked on its page, as a lifter does it: only what the page
/// offers is tapped (the shown row's check, a row of "REMAINING"), through the store and the real engine.
/// At every step the card, the header and the list must name the same exercise, and the set that is
/// logged must be the one the card showed.
@MainActor
@Suite("Workout walked on its page (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutWalkAdversarialTests {
    typealias Bench = PumpBench

    /// What the page showed when a check was tapped.
    struct Step: Equatable, CustomStringConvertible {
        let exercise: Int
        let row: String

        var description: String {
            "\(exercise):\(row)"
        }
    }

    /// The first thing wrong with the page of `bench`, or nil: the card, the header's words, its current
    /// segment and "REMAINING" must agree on the shown exercise, and the card must read that exercise.
    static func disagreement(on bench: Bench, truth: WorkoutState) -> String? {
        guard let page = bench.store.model.page, let header = bench.store.model.header, let card = page.card else {
            return "no card"
        }
        let index = card.exerciseIndex
        let exercise = truth.exercises[index]
        let place = "Exercise \(index + 1) of \(truth.exercises.count)"
        let target = "\(exercise.targetSets) × \(exercise.targetReps) @ \(exercise.targetLoad.formatted(in: .lb))"
            + " lb · RPE \(exercise.rpe.label)"
        let current = header.segments.firstIndex { $0.state == .current }
        let checks: [(Bool, String)] = [
            (card.eyebrow == place, "the card's place is \(card.eyebrow)"),
            (header.progressValue == place, "the header says \(header.progressValue)"),
            (card.title == exercise.name, "the card is named \(card.title)"),
            (card.target == target, "the target reads \(card.target)"),
            (card.rows.map(\.id) == exercise.sets.map(\.id), "the rows are another exercise's"),
            (current == nil || current == index, "segment \(current ?? -1) is current"),
            ((page.remaining?.rows ?? []).allSatisfy { $0.exerciseIndex > index }, "the list holds the shown exercise"),
            (card.rows.count(where: { $0.state == .active }) <= 1, "two shown rows"),
            (card.steppers?.setID == card.rows.first { $0.state == .active }?.id, "the steppers are another row's")
        ]
        return checks.first { !$0.0 }?.1
    }

    /// Taps the shown row's check until the page shows none, at most `limit` times. Each tap must log the
    /// set the card showed, at the weight and reps its row read.
    static func logWhatIsShown(on bench: Bench, limit: Int = 40) async throws -> [Step] {
        var steps: [Step] = []
        while steps.count < limit, let truth = await bench.settled(), let card = bench.store.model.page?.card {
            guard let row = card.rows.first(where: { $0.state == .active }) else {
                break
            }
            let wrong = disagreement(on: bench, truth: truth)
            #expect(wrong == nil, "before tap \(steps.count + 1)")
            let set = try #require(truth.exercises[card.exerciseIndex].sets.first { $0.id == row.id })
            #expect(row.weight == set.weight.formatted(in: .lb) && row.reps == String(set.reps.value))
            bench.tap(row.check)
            await bench.store.drain()
            let expected = WorkoutEvent.setLogged(
                exerciseIndex: card.exerciseIndex, setID: row.id, weight: set.weight, reps: set.reps,
                doneAt: bench.clock.value
            )
            #expect(await bench.session.applied.last == expected, "tap \(steps.count + 1)")
            steps.append(Step(exercise: card.exerciseIndex, row: row.label))
        }
        return steps
    }

    @Test("Five solo exercises logged from the first check to the last: rule 20's order, and a page with no dead end")
    func soloWorkout_walkedToItsEnd() async throws {
        let bench = try await Bench.make()
        let steps = try await Self.logWhatIsShown(on: bench)
        let expected = [5, 3, 4, 3, 3].enumerated().flatMap { index, sets in
            (1 ... sets).map { Step(exercise: index, row: String($0)) }
        }
        #expect(steps.map(\.description) == expected.map(\.description))
        let truth = try #require(await bench.settled())
        #expect(truth.doneSets == 18 && truth.totalSets == 18)
        // The last set of the last exercise: the cursor has nowhere to go, and the page shows that exercise.
        let page = try #require(bench.store.model.page)
        #expect(page.card?.exerciseIndex == 4)
        #expect(page.card?.steppers == nil)
        #expect(page.card?.rows.map(\.state) == [.done, .done, .done])
        #expect(page.remaining == nil)
        #expect(bench.store.model.header?.segments.map(\.state) == Array(repeating: .done, count: 5))
        #expect(bench.store.model.header?.progressValue == "Exercise 5 of 5")
        bench.following.cancel()
    }

    @Test("An un-logged set of a finished workout can be logged again from the page")
    func unlog_afterTheEnd_canBeLoggedAgain() async throws {
        // Round 2: every set is logged through the page again (the fix round's sanctioned edit had logged
        // this one in the fixture); a minute then passes, so the un-log is not a second touch (criterion 18).
        let bench = try await Bench.make()
        _ = try await Self.logWhatIsShown(on: bench)
        bench.clock.withValue { $0 += 60 }
        bench.tap(.unlog(exerciseIndex: 1, setID: bench.set(1, 2)))
        await bench.store.drain()
        let again = try await Self.logWhatIsShown(on: bench)
        #expect(again.map(\.description) == ["1:3"])
        #expect(await bench.session.current()?.doneSets == 18)
        bench.following.cancel()
    }

    /// FINDING F10-S5-4 (the reviewer's S-1): a row of "REMAINING" that names an exercise with nothing left
    /// to log leads to a page with no way on. The last exercise is done first (a jump, its three sets); the
    /// page returns to the first exercise and still lists the last one; a tap on it shows a card whose every
    /// row is done, with no steppers and no "REMAINING", while thirteen sets are still to log.
    @Test("A row of REMAINING never leads to a page with nothing to log and no way on")
    func jump_toAFinishedExercise_isNoDeadEnd() async throws {
        let bench = try await Bench.make()
        bench.tap(.jump(exerciseIndex: 4))
        await bench.store.drain()
        for _ in 0 ..< 3 {
            await bench.settled()
            let row = try #require(bench.store.model.page?.card?.rows.first { $0.state == .active })
            bench.tap(row.check)
            await bench.store.drain()
        }
        await bench.settled()
        #expect(bench.store.model.page?.card?.exerciseIndex == 0, "back at the first exercise that has a set to log")
        // The lifter taps what "REMAINING" offers, each row in turn.
        for offered in bench.store.model.page?.remaining?.rows ?? [] {
            bench.tap(.jump(exerciseIndex: offered.exerciseIndex))
            await bench.store.drain()
            let truth = try #require(await bench.settled())
            let page = try #require(bench.store.model.page)
            let canLog = page.card?.steppers != nil
            let canMoveOn = page.remaining != nil
            #expect(
                canLog || canMoveOn,
                "\(offered.name): \(truth.totalSets - truth.doneSets) sets are left and the page offers none"
            )
        }
        bench.following.cancel()
    }
}

// MARK: A day with a superset (criterion 6)

extension WorkoutWalkAdversarialTests {
    /// F10 S9 (sanctioned edit, criterion 23): the first thing wrong with the block of `bench`, or nil: the
    /// header's words and current segment, the legend's current member and the steppers name the same
    /// member, and "REMAINING" lists none of the block's.
    static func blockDisagreement(on bench: Bench, truth: WorkoutState) -> String? {
        guard let page = bench.store.model.page, let header = bench.store.model.header, let block = page.block
        else {
            return "no block"
        }
        let members = block.legend.map(\.exerciseIndex)
        let current = block.legend.first(where: \.isCurrent)?.exerciseIndex
        let segment = header.segments.firstIndex { $0.state == .current }
        let checks: [(Bool, String)] = [
            (block.rows.count == members.reduce(0) { $0 + truth.exercises[$1].sets.count }, "rows are missing"),
            (block.steppers?.exerciseIndex == current, "the steppers are another member's"),
            (
                current.map { header.progressValue == "Exercise \($0 + 1) of \(truth.exercises.count)" } ?? true,
                "the header says \(header.progressValue)"
            ),
            (current == nil || segment == current, "segment \(segment ?? -1) is current"),
            ((page.remaining?.rows ?? []).allSatisfy { !members.contains($0.exerciseIndex) }, "a member is listed")
        ]
        return checks.first { !$0.0 }?.1
    }

    /// Taps the block's shown row's check until it shows none, at most `limit` times. Each tap must log the
    /// set the row showed, of the member it names.
    static func logWhatTheBlockShows(on bench: Bench, limit: Int) async throws -> [Step] {
        var steps: [Step] = []
        while steps.count < limit, let truth = await bench.settled(), let block = bench.store.model.page?.block {
            guard let row = block.rows.first(where: { $0.state == .active }) else {
                break
            }
            let wrong = blockDisagreement(on: bench, truth: truth)
            #expect(wrong == nil, "before tap \(steps.count + 1)")
            let set = try #require(truth.exercises[row.exerciseIndex].sets.first { $0.id == row.id })
            bench.tap(row.check)
            await bench.store.drain()
            let expected = WorkoutEvent.setLogged(
                exerciseIndex: row.exerciseIndex, setID: row.id, weight: set.weight, reps: set.reps,
                doneAt: bench.clock.value
            )
            #expect(await bench.session.applied.last == expected, "tap \(steps.count + 1)")
            steps.append(Step(exercise: row.exerciseIndex, row: row.label))
        }
        return steps
    }

    @Test("A superset drawn as one block: every check logs the row it showed, round by round")
    func superset_walkedRoundByRound() async throws {
        let seed = try Fixtures.seedSession()
        #expect(seed.exercises[4].isSupersetWithPrevious, "Upper A ends with a superset")
        let bench = try await Bench.make { $0 = seed }
        bench.tap(.jump(exerciseIndex: 3))
        await bench.store.drain()
        let steps = try await Self.logWhatTheBlockShows(on: bench, limit: 6)
        // The engine's rounds: A1, B1, A2, B2, A3, B3.
        #expect(steps.map(\.description) == ["3:A1", "4:B1", "3:A2", "4:B2", "3:A3", "4:B3"])
        let truth = try #require(await bench.settled())
        #expect(truth.exercises[3].sets.allSatisfy(\.isDone) && truth.exercises[4].sets.allSatisfy(\.isDone))
        #expect(truth.doneSets == 6)
        // Both members done: the page goes to the first exercise that has a set to log.
        #expect(bench.store.model.page?.card?.exerciseIndex == 0)
        let wrong = Self.disagreement(on: bench, truth: truth)
        #expect(wrong == nil)
        bench.following.cancel()
    }

    @Test("In a superset a stepper, \"+ Add set\" and a jump to the second member act on the member shown")
    func superset_editsActOnTheShownMember() async throws {
        let seed = try Fixtures.seedSession()
        let bench = try await Bench.make { $0 = seed }
        bench.tap(.jump(exerciseIndex: 4))
        await bench.store.drain()
        await bench.settled()
        let block = try #require(bench.store.model.page?.block)
        let shown = try #require(block.steppers?.setID)
        #expect(block.steppers?.exerciseIndex == 4 && shown == seed.exercises[4].sets[0].id)
        #expect(block.current?.exerciseIndex == 4)
        bench.tap(.stepReps(exerciseIndex: 4, setID: shown, .increment), .addSet(exerciseIndex: 4))
        await bench.store.drain()
        let truth = try #require(await bench.settled())
        #expect(truth.exercises[4].sets.count == seed.exercises[4].sets.count + 1)
        #expect(truth.exercises[4].sets[0].reps.value == seed.exercises[4].sets[0].reps.value + 1)
        let isUntouched = truth.exercises[3] == seed.exercises[3]
        #expect(isUntouched, "the first member was changed")
        let lengths = [seed.exercises[3].sets.count, seed.exercises[4].sets.count + 1]
        #expect(bench.store.model.header?.segments.map(\.length).suffix(2) == lengths)
        #expect(Self.blockDisagreement(on: bench, truth: truth) == nil)
        bench.following.cancel()
    }
}
