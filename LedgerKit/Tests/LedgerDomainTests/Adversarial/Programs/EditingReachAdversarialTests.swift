import Foundation
@testable import LedgerDomain
import Testing

/// The seeded suites compare `ProgramEditing` and `DayEditing` with a model, which proves nothing about a
/// rule the seeds never meet. These two tests replay the first forty seeds on the models alone and name
/// every rule they met, so a generator that stops reaching a rule fails here (testing-strategy §6: a fixed
/// list of seeds is shown to reach every case).
@Suite("The seeded edit sequences reach every rule (adversarial)", .tags(.domain, .property))
struct EditingReachAdversarialTests {
    static let seeds = PropertySeed.all.prefix(40)

    /// The rules one block edit met, from the model before and after it.
    static func blockRules(
        _ edit: BlockEdit,
        before: BlockModel,
        after: BlockModel,
        error: ProgramEditError?
    ) -> [String] {
        let trained = [before, after].map { $0.weeks.map(\.schedule.count).reduce(0, +) }
        let days = [before.days.count, after.days.count]
        let weeks = [before.weeks.count, after.weeks.count]
        var kind = "other"
        if case .cycle = edit {
            kind = "cycle"
        } else if case .addWeek = edit {
            kind = "addWeek"
        } else if case .days(.add) = edit {
            kind = "addDay"
        }
        let checks: [(String, Bool)] = [
            ("the minimum of two weeks", error == .minimumTwoWeeks),
            ("a logged last week", error != nil && error != .minimumTwoWeeks),
            ("a week removed", weeks[1] < weeks[0]),
            ("a week added", weeks[1] > weeks[0]),
            ("a week id in use", kind == "addWeek" && weeks[1] == weeks[0]),
            ("a cycle onto a day", kind == "cycle" && trained[1] > trained[0]),
            ("a cycle back to rest", kind == "cycle" && trained[1] < trained[0]),
            ("a day added", days[1] > days[0]),
            ("a day refused", kind == "addDay" && days[1] == days[0]),
            ("a tag past the count", days[1] > days[0] && after.days.last?.tag != "D\(days[1])"),
            ("a scheduled day deleted", days[1] < days[0] && trained[1] < trained[0]),
            ("a block with no days", after.days.isEmpty)
        ]
        return checks.filter(\.1).map(\.0)
    }

    /// The rules one day edit met, from the model before and after it.
    static func dayRules(_ edit: DayEdit, before: DayModel, after: DayModel) -> [String] {
        let groups = [before.groups.count, after.groups.count]
        let slots = [before.ids.count, after.ids.count]
        let sameSets = before.groups.map(Set.init) == after.groups.map(Set.init)
        var asked = 0
        var kind = "other"
        if case let .add(rows, _) = edit {
            asked = rows.count
            kind = "add"
        } else if case .superset = edit {
            kind = "superset"
        } else if case .move = edit {
            kind = "move"
        }
        let tops = after.ids.filter { before.rows[$0]?.repsHi != after.rows[$0]?.repsHi && before.rows[$0] != nil }
        let reps = after.ids.filter { before.rows[$0]?.reps != after.rows[$0]?.reps && before.rows[$0] != nil }
        let checks: [(String, Bool)] = [
            ("a slot added", slots[1] > slots[0]),
            ("an added id left out", kind == "add" && slots[1] - slots[0] < asked),
            ("a slot joined on arrival", kind == "add" && groups[1] - groups[0] < slots[1] - slots[0]),
            ("a slot removed", slots[1] < slots[0]),
            ("the last slot removed", slots[0] > 0 && slots[1] == 0),
            ("two groups joined", kind == "superset" && groups[1] < groups[0]),
            ("a group split", kind == "superset" && groups[1] > groups[0]),
            ("two members swapped", kind == "move" && before.groups != after.groups && sameSets),
            ("two groups swapped", kind == "move" && !sameSets),
            ("a move at the day's edge", kind == "move" && before.groups == after.groups && slots[0] > 0),
            ("the top pushed by reps", !tops.isEmpty && !reps.isEmpty),
            ("the top changed alone", !tops.isEmpty && reps.isEmpty)
        ]
        return checks.filter(\.1).map(\.0)
    }
}

extension EditingReachAdversarialTests {
    @Test(
        "Forty seeds of block edits meet both errors, an id in use, a skipped tag and a deleted scheduled day."
    )
    func blockSequences_reachEveryRule() throws {
        var reached: Set<String> = []
        for seed in Self.seeds {
            var generator = seed.generator
            var model = try BlockModel(ProgramEditingModelAdversarialTests.start(using: &generator))
            for step in 0 ..< 60 {
                let edit = ProgramEditingModelAdversarialTests.randomEdit(model, step: step, using: &generator)
                let before = model
                let error = model.apply(edit)
                reached.formUnion(Self.blockRules(edit, before: before, after: model, error: error))
            }
        }
        let wanted: Set = [
            "the minimum of two weeks", "a logged last week", "a week removed", "a week added", "a week id in use",
            "a cycle onto a day", "a cycle back to rest", "a day added", "a day refused", "a tag past the count",
            "a scheduled day deleted", "a block with no days"
        ]
        #expect(reached == wanted, "never met: \(wanted.subtracting(reached).sorted())")
    }

    @Test(
        "Forty seeds of day edits meet every way a day changes: adds, removals, joins, splits, moves, the coupling."
    )
    func daySequences_reachEveryRule() {
        var reached: Set<String> = []
        for seed in Self.seeds {
            var generator = seed.generator
            var model = DayEditingModelAdversarialTests.start(using: &generator)
            for step in 0 ..< 80 {
                let edit = DayEdit.random(ids: model.ids, step: step, using: &generator)
                let before = model
                edit.apply(to: &model)
                reached.formUnion(Self.dayRules(edit, before: before, after: model))
            }
        }
        let wanted: Set = [
            "a slot added", "an added id left out", "a slot joined on arrival", "a slot removed",
            "the last slot removed", "two groups joined", "a group split", "two members swapped",
            "two groups swapped", "a move at the day's edge", "the top pushed by reps", "the top changed alone"
        ]
        #expect(reached == wanted, "never met: \(wanted.subtracting(reached).sorted())")
    }
}
