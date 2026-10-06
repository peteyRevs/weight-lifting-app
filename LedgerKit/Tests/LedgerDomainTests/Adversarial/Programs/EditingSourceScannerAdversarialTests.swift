import Foundation
@testable import LedgerDomain
import Testing

/// Criterion 15's source test, attacked through its own scanner (`EditingSourceTests`, read only after the
/// round's other tests existed). Each sample is a change a later slice could make under
/// `LedgerDomain/Programs`. The first test shows what the scanner catches; the others pin, as built, what
/// it lets through (finding F11-S1-4): they pass today and are to be turned round if the scanner is widened.
@Suite("Editing source scanner (adversarial)", .tags(.domain))
struct EditingSourceScannerAdversarialTests {
    /// The edit functions the scanner finds in `source`.
    static func edits(_ source: String) -> [String] {
        EditingSourceTests.editFunctions(in: EditingSourceTests.code(source))
    }

    /// How many lines of `source` the scanner flags outside `newSlot`.
    static func flagged(_ source: String) throws -> Int {
        try EditingSourceTests.namingWhatAWorkoutOwns(in: EditingSourceTests.code(source), file: "S.swift").outside
            .count
    }
}

extension EditingSourceScannerAdversarialTests {
    @Test("Caught: a new static edit by its result, and a line that names misses or exerciseID or calls Slot(.")
    func scanner_catchesTheSpellingsItWasWrittenFor() throws {
        #expect(Self.edits("static func duplicateSlot(_ day: DayTemplate) -> DayTemplate {\n}") == ["duplicateSlot"])
        #expect(Self.edits("static func reset(_ program: Program) throws(ProgramEditError) -> Program {") == ["reset"])
        #expect(try Self.flagged("slots[index].misses.removeAll()") == 1)
        #expect(try Self.flagged("edited.exerciseID = other") == 1)
        #expect(try Self.flagged("let copy = try? Slot(id: id, exerciseID: exercise)") == 1)
    }

    @Test("Pinned as built (F11-S1-4): an edit that is not a static func, or whose result is wrapped, is not found.")
    func scanner_missesEditsItDoesNotRecognise() {
        let unseen = [
            "func resettingMisses() -> DayTemplate {",
            "mutating func clearMisses() {",
            "static func swapped(_ day: DayTemplate) -> DayTemplate? {",
            "static func split(_ day: DayTemplate) -> [DayTemplate] {",
            "static func merged(_ program: Program) -> (Program, Bool) {",
            "static func clear(_ program: inout Program) {",
            "static func generic<Value>(_ day: DayTemplate) -> DayTemplate where Value: Sendable {",
            "class func legacy(_ day: DayTemplate) -> DayTemplate {"
        ]
        for line in unseen {
            #expect(Self.edits(line) == [], "\(line)")
        }
    }

    @Test(
        "Pinned as built (F11-S1-4): a write that names neither field, or a Slot made without Slot(, passes."
    )
    func scanner_missesWritesThatNameNothing() throws {
        let unseen = [
            "slots[index] = slots[index - 1]",
            "slots[index] = template",
            "slots[index][keyPath: field] = value",
            "let copy: Slot = try .init(id: id, sets: 3)",
            "let decoded = try JSONDecoder().decode(Slot.self, from: data)",
            "slots = other.slots",
            "let text = \"https://example\"; slots[index].misses = []"
        ]
        for line in unseen {
            #expect(try Self.flagged(line) == 0, "\(line)")
        }
    }
}
