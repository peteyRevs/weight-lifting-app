import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 2: `cleanedName` removes every scalar of category `Cc`, trims, and is `nil` when nothing
/// is left. Expected values are written out by hand, or come from `EditAdv.referenceName`, which works scalar
/// by scalar from the definition of `Cc` (U+0000…U+001F, U+007F…U+009F).
@Suite("ProgramEditing names (adversarial)", .tags(.domain))
struct ProgramEditingNamesAdversarialTests {
    /// A typed name and what must be stored, as scalars; `nil` for a name that must not be stored.
    struct Example {
        let typed: String
        let stored: String?
    }

    static let kept: [Example] = [
        Example(typed: "Upper A", stored: "Upper A"),
        Example(typed: "  Upper A  ", stored: "Upper A"),
        Example(typed: " a  b ", stored: "a  b"),
        Example(typed: "e\u{301}", stored: "e\u{301}"),
        Example(typed: "\u{E9}", stored: "\u{E9}"),
        Example(
            typed: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} day",
            stored: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} day"
        ),
        Example(typed: "\u{200F}\u{64A}\u{648}\u{645}\u{200E}", stored: "\u{200F}\u{64A}\u{648}\u{645}\u{200E}"),
        Example(typed: "a\u{AD}b", stored: "a\u{AD}b"),
        Example(typed: "a\u{A0}b", stored: "a\u{A0}b"),
        Example(typed: "a\u{2028}b", stored: "a\u{2028}b"),
        Example(typed: "~\u{A1}", stored: "~\u{A1}")
    ]

    static let cleaned: [Example] = [
        Example(typed: "", stored: nil),
        Example(typed: " ", stored: nil),
        Example(typed: "\u{0}", stored: nil),
        Example(typed: "\u{0}\u{1F}\u{7F}\u{80}\u{9F}", stored: nil),
        Example(typed: " \u{0} \t \u{85} ", stored: nil),
        Example(typed: "\r\n", stored: nil),
        Example(typed: "\u{2028}\u{2029}\u{3000}\u{A0}", stored: nil),
        Example(typed: "a\u{0}b", stored: "ab"),
        Example(typed: "a\tb", stored: "ab"),
        Example(typed: "a\nb", stored: "ab"),
        Example(typed: "a\r\nb", stored: "ab"),
        Example(typed: "\u{7F}a\u{9F}", stored: "a"),
        Example(typed: "a\u{80}b\u{85}c", stored: "abc"),
        Example(typed: " \u{0} a \u{1} ", stored: "a"),
        Example(typed: "\u{0} a b \u{0}", stored: "a b"),
        Example(typed: "a\u{0}\u{301}b", stored: "a\u{301}b"),
        Example(typed: "a\u{A0}", stored: "a"),
        Example(typed: "\u{3000}a\u{2003}", stored: "a"),
        Example(typed: "\u{2028}a\u{2029}", stored: "a"),
        Example(typed: "\u{1F3CB}\u{FE0F}\u{0}", stored: "\u{1F3CB}\u{FE0F}")
    ]

    static func scalars(_ text: String?) -> [Unicode.Scalar]? {
        text.map { Array($0.unicodeScalars) }
    }

    /// The scalars a typed name is likely to hold, and the ones on each side of every boundary of `Cc`.
    static let pool: [Unicode.Scalar] = [
        0x0, 0x1, 0x9, 0xA, 0xD, 0x1F, 0x20, 0x41, 0x61, 0x7E, 0x7F, 0x80, 0x85, 0x9F, 0xA0, 0xA1, 0xAD,
        0x301, 0x64A, 0x200B, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0x3000, 0xFE0F, 0xFEFF, 0x1F3CB
    ].compactMap { Unicode.Scalar($0 as UInt32) }

    static func text(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}

extension ProgramEditingNamesAdversarialTests {
    @Test("Names with nothing to remove are stored as typed, scalar for scalar.")
    func cleanedName_nothingToRemove_isStoredAsTyped() {
        for example in Self.kept {
            let stored = Self.scalars(ProgramEditing.cleanedName(example.typed))
            #expect(
                stored == Self.scalars(example.stored),
                "typed \(example.typed.unicodeScalars.map(EditAdv.codePoint))"
            )
        }
    }

    @Test("Control characters are removed wherever they are, then the ends are trimmed; a blank name is nil.")
    func cleanedName_controlCharactersAndBlanks_areRemoved() {
        for example in Self.cleaned {
            let stored = Self.scalars(ProgramEditing.cleanedName(example.typed))
            #expect(
                stored == Self.scalars(example.stored),
                "typed \(example.typed.unicodeScalars.map(EditAdv.codePoint))"
            )
        }
    }

    @Test(
        "Every scalar of the first plane, alone, inside a name and at both ends of one, is cleaned as defined."
    )
    func cleanedName_everyScalarOfThePlane_matchesTheDefinition() {
        var tally = Tally()
        let astral = stride(from: UInt32(0x10000), through: 0x10FFFF, by: 257)
        for value in Array(UInt32(0) ... 0xFFFF) + Array(astral) {
            guard let scalar = Unicode.Scalar(value) else {
                continue
            }
            let one = String(Character(scalar))
            for typed in [one, "a" + one + "b", one + "x" + one] {
                let stored = ProgramEditing.cleanedName(typed)
                tally.check(
                    EditAdv.isReferenceName(stored, for: typed),
                    "\(EditAdv.codePoint(scalar)) in a name of \(typed.unicodeScalars.count)"
                )
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases > 190_000)
    }

    @Test(
        "Seeded names over the boundary scalars are cleaned as the definition says; cleaning twice changes nothing.",
        arguments: PropertySeed.all
    )
    func cleanedName_seededNames_matchTheDefinition(seed: PropertySeed) {
        var generator = seed.generator
        var tally = Tally()
        for _ in 0 ..< 40 {
            let length = Int.random(in: 0 ... 10, using: &generator)
            let typed = Self.text((0 ..< length).compactMap { _ in Self.pool.randomElement(using: &generator) })
            let stored = ProgramEditing.cleanedName(typed)
            let codes = typed.unicodeScalars.map(EditAdv.codePoint)
            tally.check(EditAdv.isReferenceName(stored, for: typed), "\(codes)")
            if let stored {
                let again = ProgramEditing.cleanedName(stored)
                tally.check(Self.scalars(again) == Self.scalars(stored), "cleaned twice: \(codes)")
                tally.check(
                    !stored.unicodeScalars.contains(where: EditAdv.isControl),
                    "a control character is left: \(codes)"
                )
            }
        }
        #expect(tally.passed, "\(seed): \(tally.summary)")
    }

    @Test(
        "Pinned as built, not as specified: a name of invisible format characters alone is stored (finding F11-S1-1)."
    )
    func cleanedName_formatCharactersAlone_isStored() {
        // Category Cf and blank-looking letters are not Cc and are not white space, so the rule keeps them.
        for typed in ["\u{200E}", "\u{2060}\u{FEFF}", "\u{AD}", "\u{200D}", "\u{3164}", "\u{2800}"] {
            let stored = Self.scalars(ProgramEditing.cleanedName(typed))
            #expect(stored == Self.scalars(typed), "typed \(typed.unicodeScalars.map(EditAdv.codePoint))")
        }
    }

    @Test("A name of 300,000 scalars with a control character in every seventh place loses exactly those.")
    func cleanedName_veryLongName_losesOnlyTheControlCharacters() throws {
        let nul = try #require(Unicode.Scalar(UInt32(0)))
        let letter = try #require(Unicode.Scalar(UInt32(0x62)))
        let typed = Self.text((0 ..< 300_000).map { $0 % 7 == 3 ? nul : letter })
        let stored = try #require(ProgramEditing.cleanedName(typed))
        #expect(stored.unicodeScalars.count == 300_000 - 42857)
        #expect(stored.unicodeScalars.allSatisfy { $0 == letter })
    }

    @Test("renameProgram, renameDay and addDay store exactly what cleanedName gives, for every boundary scalar.")
    func rename_storesTheCleanedName() throws {
        let program = try EditAdv.fourDayProgram()
        let day = EditAdv.fourDayIDs[0]
        var tally = Tally()
        for scalar in Self.pool {
            let typed = Self.text([scalar]) + " Push" + Self.text([scalar]) + "day "
            let expected = EditAdv.referenceNameText(typed) ?? program.name
            let renamed = ProgramEditing.renameProgram(program, to: typed)
            tally.check(Self.scalars(renamed.name) == Self.scalars(expected), "program, \(EditAdv.codePoint(scalar))")
            let dayRenamed = ProgramEditing.renameDay(program, day: day, to: typed)
            tally.check(
                Self.scalars(dayRenamed.days[0].name) == Self.scalars(expected),
                "day, \(EditAdv.codePoint(scalar))"
            )
            let added = ProgramEditing.addDay(program, id: EditAdv.dayID(340), name: typed)
            tally.check(
                Self.scalars(added.days.last?.name) == Self.scalars(expected),
                "added day, \(EditAdv.codePoint(scalar))"
            )
        }
        #expect(tally.passed, tally.summary)
    }
}
