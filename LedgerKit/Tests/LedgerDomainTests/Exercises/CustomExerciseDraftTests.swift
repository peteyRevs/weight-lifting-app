import Foundation
@testable import LedgerDomain
import Testing

/// F12 S3, criterion 9 and N15: `CustomExerciseDraft`, the lifter's exercise built from what the form holds, with
/// the fields it does not ask for as Pete's question 4 settles them (A/A).
@Suite("CustomExerciseDraft", .tags(.domain))
struct CustomExerciseDraftTests {
    static let id = ExerciseID(Fixtures.uuid(7001))

    /// A live exercise named `name`.
    static func live(_ number: Int, _ name: String) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(7100 + number)),
            name: name,
            shortName: name,
            equipment: .barbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(45)]
        )
    }

    static func error(_ draft: CustomExerciseDraft, among live: [Exercise] = []) -> CustomExerciseError? {
        do {
            _ = try draft.exercise(id: id, among: live)
            return nil
        } catch {
            return error
        }
    }

    @Test("Criterion 9: the draft builds the lifter's exercise, with the name as the short name and a start of 0")
    func buildsCustomExercise() throws {
        let draft = CustomExerciseDraft(
            name: "  Landmine Squeeze Press \n",
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            pattern: .horizontalPush
        )
        let built = try draft.exercise(id: Self.id, among: [Self.live(1, "Barbell Bench Press")])
        #expect(built == Exercise(
            id: Self.id,
            name: "Landmine Squeeze Press",
            shortName: "Landmine Squeeze Press",
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .zero, .kg: .zero],
            isCustom: true,
            curatedAlternatives: []
        ))
        #expect(built.startLoad(in: .lb) == .zero && built.startLoad(in: .kg) == .zero)
    }

    @Test("A new draft has no name and each choice the first of its kind")
    func newDraft_defaults() {
        let draft = CustomExerciseDraft()
        #expect(draft.name.isEmpty && draft.secondaryMuscles.isEmpty)
        #expect(draft.equipment == .barbell && draft.primaryMuscle == .chest && draft.pattern == .horizontalPush)
    }

    @Test("A stored exercise's draft builds it again: an edit that changes nothing stores what was there")
    func draftOfAnExercise_buildsItAgain() throws {
        let stored = try CustomExerciseDraft(
            name: "Cable Y Raise",
            equipment: .cable,
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            pattern: .isolation
        ).exercise(id: Self.id, among: [])
        let draft = CustomExerciseDraft(stored)
        #expect(draft.name == "Cable Y Raise" && draft.secondaryMuscles == [.back])
        #expect(try draft.exercise(id: Self.id, among: [stored]) == stored)
    }

    @Test("A blank name is refused", arguments: ["", " ", "   \t", "\n\u{2003}"])
    func name_blank_isRefused(_ name: String) {
        #expect(Self.error(CustomExerciseDraft(name: name)) == .blankName)
    }

    @Test("A trimmed name of 2 to 40 characters, counted as the lifter sees them, is taken; 1 and 41 are not")
    func name_length() {
        #expect(Self.error(CustomExerciseDraft(name: "A")) == .nameLength(1))
        #expect(Self.error(CustomExerciseDraft(name: " Ab ")) == nil)
        #expect(Self.error(CustomExerciseDraft(name: String(repeating: "x", count: 40))) == nil)
        #expect(Self.error(CustomExerciseDraft(name: String(repeating: "x", count: 41))) == .nameLength(41))
        // "é" written decomposed is one character; so is a flag, two scalars.
        #expect(Self.error(CustomExerciseDraft(name: "e\u{301}")) == .nameLength(1))
        #expect(Self.error(CustomExerciseDraft(name: String(repeating: "🇫🇷", count: 40))) == nil)
        #expect(Self.error(CustomExerciseDraft(name: String(repeating: "e\u{301}", count: 41))) == .nameLength(41))
    }

    @Test("A name holding a control character is refused, U+0000 among them", arguments: [
        "Row\u{0}ing", "Row\ting", "Row\ning", "Press\u{7F}", "Press\u{85}x", "\u{1B}[0m Squat"
    ])
    func name_controlCharacter_isRefused(_ name: String) {
        #expect(Self.error(CustomExerciseDraft(name: name)) == .controlCharacter)
    }

    @Test("A name another live exercise has, ignoring case, diacritics and width, is refused")
    func name_duplicate_isRefused() {
        let bench = Self.live(1, "Barbell Bench Press")
        let elevation = Self.live(2, "Élévation")
        for name in ["barbell bench press", " BARBELL BENCH PRESS ", "ｂａｒｂｅｌｌ ｂｅｎｃｈ ｐｒｅｓｓ"] {
            #expect(Self.error(CustomExerciseDraft(name: name), among: [bench]) == .duplicateName(bench.id))
        }
        #expect(Self
            .error(CustomExerciseDraft(name: "elevation"), among: [elevation]) == .duplicateName(elevation.id))
        #expect(Self.error(CustomExerciseDraft(name: "Barbell Bench Presses"), among: [bench]) == nil)
    }

    @Test("An edit may keep its own name, and may not take another's")
    func name_edit_keepsItsOwn() {
        let own = Exercise(
            id: Self.id, name: "Landmine Squeeze Press", shortName: "LM", equipment: .barbell,
            primaryMuscle: .chest, pattern: .horizontalPush, defaultStartLoad: [:], isCustom: true
        )
        let other = Self.live(1, "Barbell Bench Press")
        #expect(Self.error(CustomExerciseDraft(name: "landmine squeeze press"), among: [own, other]) == nil)
        #expect(Self.error(CustomExerciseDraft(name: "Barbell bench press"), among: [own, other])
            == .duplicateName(other.id))
    }

    @Test("The primary muscle is never among the secondary ones")
    func muscles_primaryAmongSecondaries_isRefused() {
        let draft = CustomExerciseDraft(name: "Hip Thrust Hold", primaryMuscle: .glutes, secondaryMuscles: [.glutes])
        #expect(Self.error(draft) == .primaryAmongSecondaries)
        #expect(Self.error(CustomExerciseDraft(name: "Hip Thrust Hold", primaryMuscle: .glutes)) == nil)
    }

    @Test("The checks run in order: blank, length, control character, duplicate, then the muscles")
    func checks_runInOrder() {
        let bench = Self.live(1, "Barbell Bench Press")
        let both = CustomExerciseDraft(name: "Barbell Bench Press", secondaryMuscles: [.chest])
        #expect(Self.error(both, among: [bench]) == .duplicateName(bench.id))
        #expect(Self.error(CustomExerciseDraft(name: "\u{0}")) == .nameLength(1))
        #expect(Self.error(CustomExerciseDraft(name: "Barbell\tBench Press"), among: [bench]) == .controlCharacter)
    }
}
