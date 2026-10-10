@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S5 criteria 2, 6, 11 and 12: the tester's own model of the page against `WorkoutPresentation`,
/// on workouts no preview draws: kilograms with a drop set in the middle, twelve sets, a cursor and a
/// choice that name nothing, a slot with no set; counted texts under other languages; other time zones.
@MainActor
@Suite("Workout page (adversarial)", .tags(.feature))
struct WorkoutPageAdversarialTests {
    typealias Context = WorkoutPresentation.Context

    static func context(_ locale: Locale = Fixtures.locale, zone: String = "UTC") throws -> Context {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return WorkoutPresentation.Context(locale: locale, calendar: calendar)
    }

    /// Twelve rows of 82.5 kg × 7 with a drop set as the fifth, the first three logged, RPE 8.5, done last
    /// on 2026-08-12 at 23:30 UTC; then a second exercise with a drop set at its end.
    static func kilograms() throws -> WorkoutState {
        var state = EventBuilders.seedSession()
        state.units = .kg
        state.exercises = Array(state.exercises.prefix(2))
        let id = state.exercises[0].id
        state.exercises[0].sets = (0 ..< 12).map { row in
            LoggedSet(
                id: .derived(from: id, index: row),
                weight: .kilograms(row == 4 ? 70 : 82.5),
                reps: Reps(clamping: row == 4 ? 9 : 7),
                kind: row == 4 ? .drop : .working,
                doneAt: row < 3 ? Fixtures.now : nil
            )
        }
        state.exercises[0].targetSets = 11
        state.exercises[0].targetReps = 7
        state.exercises[0].targetLoad = .kilograms(82.5)
        state.exercises[0].rpe = try #require(RPE(8.5))
        state.exercises[0].step = .kilograms(2.5)
        state.exercises[0].lastPerformance = LastPerformance(
            date: Date(timeIntervalSince1970: 1_786_577_400), sets: 11, reps: 6, load: .kilograms(80)
        )
        state.exercises[1].sets[2].kind = .drop
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 3)
        return state
    }

    @Test("Kilograms, twelve rows and a drop set in the middle: every text of the card, character for character")
    func card_inKilograms_wordForWord() throws {
        let page = try WorkoutPresentation.page(Self.kilograms(), selection: nil, isBusy: false, Self.context())
        let card = try #require(page.card)
        #expect(card.eyebrow == "Exercise 1 of 2")
        #expect(card.title == "Barbell Bench Press")
        #expect("\(card.targetLabel) \(card.target)" == "TARGET 11 × 7 @ 82.5 kg · RPE 8.5")
        #expect("\(card.lastLabel) \(card.last)" == "Last Aug 12 · 11×6 @ 80 kg")
        #expect(card.repeatLast == "Repeat")
        #expect("\(card.columns.number) \(card.columns.weight) \(card.columns.reps)" == "# kg reps")
        #expect(card.rows.map(\.label) == ["1", "2", "3", "4", "D", "5", "6", "7", "8", "9", "10", "11"])
        #expect(card.rows.map(\.state).prefix(5) == [.done, .done, .done, .active, .pending])
        #expect(card.rows[3].summary == "Set 4, 82.5 kilograms, 7 reps")
        #expect(card.rows[4].summary == "Drop set, 70 kilograms, 9 reps")
        #expect("\(card.rows[4].weight) × \(card.rows[4].reps)" == "70 × 9")
        #expect(card.rows.map(\.checkLabel).prefix(6) == [
            "Undo set 1", "Undo set 2", "Undo set 3", "Log set 4", "Log drop set", "Log set 5"
        ])
        #expect(card.rows.last?.checkLabel == "Log set 11")
        let steppers = try #require(card.steppers)
        #expect("\(steppers.weightStep) / \(steppers.repStep)" == "2.5 KG / 1 REP")
        #expect("\(steppers.weight) / \(steppers.reps)" == "82.5 kilograms / 7 reps")
        #expect(card.addSet == "+ Add set")
        #expect(page.remaining?.title == "REMAINING")
        #expect(page.remaining?.rows.map { "\($0.name), \($0.scheme)" } == ["Incline DB Press, 3 × 10"])
    }

    @Test("The day of \"Last\" is the handed calendar's, whatever zone the machine is in", arguments: [
        ("UTC", "Aug 12"), ("Asia/Tokyo", "Aug 13"), ("America/Los_Angeles", "Aug 12"), ("Pacific/Kiritimati", "Aug 13")
    ])
    func last_readsNoAmbientZone(zone: String, day: String) throws {
        let state = try Self.kilograms()
        let ambient = NSTimeZone.default
        defer { NSTimeZone.default = ambient }
        var lines: Set<String> = []
        for machine in ["Pacific/Pago_Pago", "Pacific/Kiritimati"] {
            NSTimeZone.default = try #require(TimeZone(identifier: machine))
            let card = try WorkoutPresentation.card(of: 0, in: state, selection: nil, Self.context(zone: zone))
            lines.insert(card.last)
        }
        #expect(lines == ["\(day) · 11×6 @ 80 kg"])
    }

    @Test(
        "A count of reps takes the form of the catalog's language, which is English, under every language",
        arguments: ["en_US", "ja_JP", "ru_RU", "pl_PL", "fr_FR", "ar_SA", "cy_GB"]
    )
    func reps_takeTheCatalogsPluralForm(identifier: String) throws {
        var state = try Self.kilograms()
        for (row, reps) in [1, 2, 5, 21, 0].enumerated() {
            state.exercises[0].sets[row + 5].reps = Reps(clamping: reps)
        }
        let context = try Self.context(Locale(identifier: identifier))
        let rows = WorkoutPresentation.card(of: 0, in: state, selection: nil, context).rows
        let words = rows[5 ... 9].map { $0.summary.split(separator: " ").last.map(String.init) ?? "" }
        // Reps are at least one by type: the fifth row's 0 is held at 1.
        #expect(words == ["rep", "reps", "reps", "reps", "rep"])
    }

    /// A workout the engine would not build: sets taken away, cursors and choices that name nothing.
    static func broken(seed: UInt64) -> (state: WorkoutState, selection: WorkoutSelection?) {
        var generator = SplitMix64(seed: seed)
        var state = EventBuilders.seedSession()
        state.exercises = Array(state.exercises.prefix(Int.random(in: 0 ... 5, using: &generator)))
        for index in state.exercises.indices {
            state.exercises[index].sets = Array(
                state.exercises[index].sets.prefix(Int.random(in: 0 ... 5, using: &generator))
            )
            for row in state.exercises[index].sets.indices where Bool.random(using: &generator) {
                state.exercises[index].sets[row].doneAt = Fixtures.now
            }
        }
        let anywhere = { (generator: inout SplitMix64) in Int.random(in: -2 ... 6, using: &generator) }
        state.cursor = Bool.random(using: &generator)
            ? nil : Cursor(exerciseIndex: anywhere(&generator), setIndex: anywhere(&generator))
        let sets = EventBuilders.seedSession().exercises.flatMap(\.sets).map(\.id)
        let chosen: SetID? = Bool.random(using: &generator) ? sets.randomElement(using: &generator) : nil
        let selection = Bool.random(using: &generator)
            ? nil : WorkoutSelection(exerciseIndex: anywhere(&generator), setID: chosen)
        return (state, selection)
    }

    @Test("Any workout, cursor and choice give a page that does not trap and does not contradict itself")
    func page_isTotal() throws {
        let context = try Self.context()
        for seed in UInt64(0) ..< 400 {
            let (state, selection) = Self.broken(seed: seed)
            let page = WorkoutPresentation.page(state, selection: selection, isBusy: false, context)
            let header = WorkoutPresentation.header(state, isBusy: false, locale: context.locale, selection: selection)
            let listed = (page.remaining?.rows ?? []).map(\.exerciseIndex)
            guard let card = page.card else {
                #expect(listed == Array(state.exercises.indices), "seed \(seed): with no card every exercise is listed")
                #expect(header.progressValue.isEmpty, "seed \(seed)")
                continue
            }
            let exercise = state.exercises[card.exerciseIndex]
            let active = card.rows.filter { $0.state == .active }
            let isOpen = exercise.sets.contains { $0.id == card.steppers?.setID && !$0.isDone }
            #expect(card.rows.map(\.id) == exercise.sets.map(\.id), "seed \(seed)")
            #expect(active.count <= 1 && active.first?.id == card.steppers?.setID, "seed \(seed)")
            #expect(card.steppers == nil || isOpen, "seed \(seed): the steppers are on a logged row")
            #expect(
                (card.steppers == nil) == exercise.sets.allSatisfy(\.isDone),
                "seed \(seed): an open row, no steppers"
            )
            #expect(listed == Array(state.exercises.indices.filter { $0 > card.exerciseIndex }), "seed \(seed)")
            #expect(header.progressValue == card.eyebrow, "seed \(seed)")
            #expect(zip(card.rows, exercise.sets).allSatisfy { ($0.state == .done) == $1.isDone }, "seed \(seed)")
        }
    }
}

extension WorkoutPageAdversarialTests {
    @Test("Every tap the page can send, on any such workout, comes to a plan without trapping")
    func plan_isTotal() {
        let edits: [(Int, SetID) -> WorkoutEdit] = [
            { .select(exerciseIndex: $0, setID: $1) }, { .log(exerciseIndex: $0, setID: $1) },
            { .unlog(exerciseIndex: $0, setID: $1) }, { .stepWeight(exerciseIndex: $0, setID: $1, .decrement) },
            { .stepReps(exerciseIndex: $0, setID: $1, .decrement) }, { index, _ in .repeatLast(exerciseIndex: index) },
            { index, _ in .addSet(exerciseIndex: index) }, { index, _ in .jump(exerciseIndex: index) }
        ]
        let sets = EventBuilders.seedSession().exercises.flatMap(\.sets).map(\.id)
        var events = 0
        for seed in UInt64(0) ..< 200 {
            let (state, selection) = Self.broken(seed: seed)
            for index in -1 ... 5 {
                for edit in edits {
                    let set = sets[Int(seed) % sets.count]
                    let plan = WorkoutEditPlan.make(
                        edit(index, set),
                        in: state,
                        selection: selection,
                        now: Fixtures.now
                    ) {
                        SetID(EventBuilders.uuid(1))
                    }
                    events += plan.events.count
                }
            }
        }
        #expect(events > 500, "the workouts of these seeds gave the plans too little to do")
    }

    @Test("An exercise with no set: the card has no row, and \"+ Add set\" gives it one of 0 × 8")
    func noSet_addSet() throws {
        var state = EventBuilders.seedSession()
        state.exercises[0].sets = []
        let page = try WorkoutPresentation.page(state, selection: nil, isBusy: false, Self.context())
        // The cursor (0, 0) names no row now: no card, and every exercise is listed, the empty one too.
        #expect(page.card == nil)
        #expect(page.remaining?.rows.count == 5)
        let shown = WorkoutSelection(exerciseIndex: 0, setID: nil)
        let card = try #require(WorkoutPresentation.page(state, selection: shown, isBusy: false, Self.context()).card)
        #expect(card.rows.isEmpty && card.steppers == nil)
        let plan = WorkoutEditPlan.make(.addSet(exerciseIndex: 0), in: state, selection: shown, now: Fixtures.now) {
            SetID(EventBuilders.uuid(5))
        }
        #expect(plan.events == [.setAdded(exerciseIndex: 0, set: LoggedSet(
            id: SetID(EventBuilders.uuid(5)), weight: .zero, reps: Reps(clamping: 8), kind: .added
        ))])
    }
}
