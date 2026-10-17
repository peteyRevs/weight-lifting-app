import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 15: criterion 12 cannot be escaped. That no edit changes the misses or the exercise
/// of a slot that already exists is proved by a property over two hand-written tables of edits
/// (`EditingTestSupport.dayEdits` and `programEdits`), and a function added later is in them only if its
/// author remembers. This suite reads the sources of `LedgerDomain/Programs`, as `ModuleBoundaryTests` reads
/// the module's imports (read-only, inside the repository), and fails when a function that returns a program
/// or a day is in neither table, or when a line outside `newSlot` names a slot's misses or its exercise, or
/// builds a `Slot`.
///
/// The second check is by name, so it also refuses a line that only reads them: no edit has a reason to, and
/// one that finds a reason is decided here, in sight of criterion 12.
@Suite("Editing sources", .tags(.domain))
struct EditingSourceTests {
    private typealias Support = EditingTestSupport

    private static let sourcesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent() // Programs
        .deletingLastPathComponent() // LedgerDomainTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LedgerKit
        .appending(path: "Sources/LedgerDomain/Programs", directoryHint: .isDirectory)

    /// Functions that return a day or a program and are no edit of their own: the edits of the two tables
    /// run through them, so the property draws them with every row.
    static let helpers: Set<String> = ["editing", "normalized"]

    /// The row of `dayEdits` that names no function: `set` given the field `stepped` returns.
    static let composedRows = ["set(stepped)"]

    /// A source text as its code: every line without its comment.
    static func code(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
        }
    }

    /// The name a line declares with `static func`, or nil.
    static func functionName(in line: String) -> String? {
        guard let keyword = line.range(of: "static func ") else {
            return nil
        }
        let name = line[keyword.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// The names of the `static func`s whose result is a `Program` or a `DayTemplate`. A signature may run
    /// over several lines and hold closure types; its result is what follows its last arrow, up to the brace
    /// that opens the body.
    static func editFunctions(in lines: [String]) -> [String] {
        lines.indices.compactMap { index in
            guard let name = functionName(in: lines[index]) else {
                return nil
            }
            let rest = lines[index...]
            let signature = rest.prefix { !$0.contains("{") }.joined(separator: " ")
                + " " + (rest.first { $0.contains("{") } ?? "")
            let result = signature.components(separatedBy: "->").last?
                .components(separatedBy: "{").first?
                .trimmingCharacters(in: .whitespaces)
            return result == "Program" || result == "DayTemplate" ? name : nil
        }
    }

    /// The lines of `function`, from its declaration to the brace that closes its body.
    static func extent(of function: String, in lines: [String]) -> ClosedRange<Int>? {
        guard let first = lines.firstIndex(where: { functionName(in: $0) == function }) else {
            return nil
        }
        var depth = 0
        var hasOpened = false
        for index in first ..< lines.count {
            depth += lines[index].count { $0 == "{" } - lines[index].count { $0 == "}" }
            hasOpened = hasOpened || lines[index].contains("{")
            if hasOpened, depth == 0 {
                return first ... index
            }
        }
        return nil
    }

    /// The code lines that name a slot's misses or exercise, or build a `Slot`: outside `newSlot` as
    /// "file:line", and how many there are inside it.
    static func namingWhatAWorkoutOwns(
        in lines: [String],
        file: String
    ) throws -> (outside: [String], insideNewSlot: Int) {
        // Simple word boundaries: by Unicode's default ones "slot.misses" is one word, and would pass unseen.
        let owned = try Regex(#"\b(misses|exerciseID)\b|\bSlot(\.init)?\("#).wordBoundaryKind(.simple)
        let allowed = extent(of: "newSlot", in: lines)
        let named = lines.indices.filter { lines[$0].contains(owned) }
        let inside = named.filter { allowed?.contains($0) == true }
        let outside = named.filter { allowed?.contains($0) != true }.map { "\(file):\($0 + 1)" }
        return (outside, inside.count)
    }

    /// Every Swift file of `LedgerDomain/Programs`, by name, as code lines.
    static func sources() throws -> [(file: String, lines: [String])] {
        try FileManager.default.contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try (file: $0.lastPathComponent, lines: code(String(contentsOf: $0, encoding: .utf8))) }
    }
}

// MARK: - The sources

extension EditingSourceTests {
    @Test("Every function of LedgerDomain/Programs that returns a program or a day is a row of the property's tables")
    func sources_everyEditIsInThePropertysTables() throws {
        let sources = try Self.sources()
        #expect(sources.count >= 5, "found \(sources.map(\.file)) under \(Self.sourcesDirectory.path)")
        let found = Set(sources.flatMap { Self.editFunctions(in: $0.lines) })
        let listed = Set(Support.dayEdits.map(\.name) + Support.programEdits.map(\.name))
        // A function named here needs a row in `EditingTestSupport.dayEdits` or `programEdits`, so that
        // criterion 12's property draws it.
        let unlisted = found.subtracting(listed).subtracting(Self.helpers).sorted()
        #expect(unlisted == [], "in neither of the property's tables")
        #expect(listed.subtracting(found).sorted() == Self.composedRows, "rows that name no function of the sources")
        #expect(Self.helpers.isSubset(of: found), "a helper named here is gone from the sources")
    }

    @Test("Outside newSlot, no line of LedgerDomain/Programs names a slot's misses or exercise, or builds a Slot")
    func sources_onlyNewSlotNamesWhatAWorkoutOwns() throws {
        let scans = try Self.sources().map { try Self.namingWhatAWorkoutOwns(in: $0.lines, file: $0.file) }
        let outside = scans.flatMap(\.outside)
        let inside = scans.map(\.insideNewSlot).reduce(0, +)
        #expect(outside == [], "criterion 12: a workout's save alone writes these")
        #expect(inside >= 2, "newSlot was not found, or no longer builds the slot")
    }
}

// MARK: - The scanner

extension EditingSourceTests {
    static let sample = """
    public enum Sample {
        /// static func inAComment() -> Program
        public static func oneLine(_ day: DayTemplate, slot: SlotID) -> DayTemplate {
            editing(day) { $0.slots[0].misses = [] } // misses in a comment
        }

        static func wrapped(
            _ program: Program,
            _ change: (DayTemplate) -> DayTemplate
        ) throws(ProgramEditError) -> Program {
            var copy = program.days[0].slots[0]
            copy.exerciseID = other
            copy.misses.insert(2)
            return program
        }

        static func takesAnEdit(_ change: (Program) -> Program) {
            let rebuilt = try? Slot(id: SlotID(uuid), exerciseID: exercise.id)
            let again = Slot.init(id: id)
        }

        private static func aSlot(_ slots: [Slot]) -> Slot {
            let made = DayEditing.newSlot(id: SlotID(uuid))
            return slots[0]
        }

        public static func newSlot(
            id: SlotID
        ) throws(SlotValidationError) -> Slot {
            try Slot(
                id: id,
                exerciseID: exercise.id,
                misses: []
            )
        }
    }
    """

    @Test("The scanner finds an edit by its result, over wrapped signatures and closure types, and skips comments")
    func scanner_findsFunctionsByTheirResult() {
        let lines = Self.code(Self.sample)
        #expect(Self.editFunctions(in: lines) == ["oneLine", "wrapped"])
        #expect(Self.functionName(in: "    public static func move(_ day: DayTemplate) -> DayTemplate {") == "move")
        #expect(Self.functionName(in: "    func instanceMethod() -> Program {") == nil)
        #expect(Self.extent(of: "wrapped", in: lines) == 6 ... 14, "counted from zero")
        #expect(Self.extent(of: "missing", in: lines) == nil)
    }

    @Test("The scanner flags a slot's misses, its exercise and a Slot built, everywhere but inside newSlot")
    func scanner_flagsWhatOnlyNewSlotMayName() throws {
        let scan = try Self.namingWhatAWorkoutOwns(in: Self.code(Self.sample), file: "Sample.swift")
        let lines = [4, 12, 13, 18, 19].map { "Sample.swift:\($0)" }
        #expect(scan.outside == lines, "assigned through an index and a variable, changed in place, built twice")
        #expect(scan.insideNewSlot == 3, "the Slot built, its exercise and its misses")
    }
}
