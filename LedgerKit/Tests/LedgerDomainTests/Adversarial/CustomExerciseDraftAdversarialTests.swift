import Foundation
@testable import LedgerDomain
import Testing

// F12 S3 adversarial round (G2): `CustomExerciseDraft`'s name rules (N15) where its own tests mirror the code. A name
// of invisible characters only; a name that draws exactly as another's but differs by an invisible character, a
// no-break space, a doubled space or a direction override; a line separator inside a name; grapheme stuffing. And
// pins of what holds: folding of case, diacritics and width, the edited exercise left out, graphemes counted, every
// `Cc` refused, the rules' order.

@Suite("Adversarial F12 S3 · CustomExerciseDraft", .tags(.domain))
struct CustomExerciseDraftAdversarialTests {
    static let id = ExerciseID(Fixtures.uuid(7801))
    static let benchID = ExerciseID(Fixtures.uuid(7802))

    static let bench = Exercise(
        id: benchID, name: "Bench Press", shortName: "Bench", equipment: .barbell,
        primaryMuscle: .chest, secondaryMuscles: [.triceps], pattern: .horizontalPush,
        defaultStartLoad: [.lb: .pounds(45)]
    )

    static func result(_ name: String, among live: [Exercise] = [bench], id: ExerciseID = id) -> CustomExerciseError? {
        do {
            _ = try CustomExerciseDraft(name: name).exercise(id: id, among: live)
            return nil
        } catch {
            return error
        }
    }

    // MARK: S3-1 · a name of invisible characters only

    @Test(
        "S3-1. A name of invisible characters only is blank: \"Enter a name.\"",
        arguments: [
            "\u{2060}\u{2060}\u{2060}", // word joiner
            "\u{FEFF}\u{FEFF}", // byte order mark, as a paste can carry
            "\u{202E}\u{202C}", // a direction override and its pop
            "\u{200E}\u{200F}" // left-to-right and right-to-left marks
        ]
    )
    func invisibleOnly_isBlank(_ name: String) {
        withKnownIssue("S3-1: format (Cf) characters are neither trimmed nor refused; an invisible name is stored") {
            let isBlank = Self.result(name) == .blankName
            #expect(isBlank, "\(name.unicodeScalars.map(\.value))")
        }
    }

    @Test("Pin: a zero-width space is trimmed (Foundation counts it a blank), alone or at the ends", arguments: [
        "\u{200B}\u{200B}", " \u{200B} \u{200B} "
    ])
    func zeroWidthSpace_isTrimmed(_ name: String) {
        #expect(Self.result(name) == .blankName)
        #expect(Self.result("Bench Press\u{200B}") == .duplicateName(Self.benchID))
    }

    // MARK: S3-2 · a name that draws as another's

    @Test(
        "S3-2. A name that draws exactly as a live exercise's is a duplicate",
        arguments: [
            "\u{FEFF}Bench Press", // a leading byte order mark survives the trim
            "Bench Press\u{2060}",
            "Bench\u{200B} Press",
            "Bench\u{00A0}Press", // a no-break space, as text copied from a web page has
            "Bench  Press", // two spaces
            "Bench\u{2009}Press" // a thin space
        ]
    )
    func drawsAsAnother_isDuplicate(_ name: String) {
        withKnownIssue("S3-2: ExerciseSearch.key folds no invisible character and no run or kind of space") {
            let isDuplicate = Self.result(name) == .duplicateName(Self.benchID)
            #expect(isDuplicate, "\(name.unicodeScalars.map(\.value))")
        }
    }

    @Test("S3-2. A right-to-left override spells a live exercise's name backwards and draws it forwards")
    func directionOverride_isDuplicate() {
        // U+202E reverses what follows on screen: "sserP hcneB" is drawn "Bench Press".
        let name = "\u{202E}sserP hcneB"
        withKnownIssue("S3-2: bidirectional format characters are kept in a name") {
            let isRefused = Self.result(name) != nil
            #expect(isRefused)
        }
    }

    // MARK: S3-3 · line separators

    @Test(
        "S3-3. A line or paragraph separator inside a name is refused, as a line break is",
        arguments: ["Bench\u{2028}Press", "Bench\u{2029}Press", "Bench\nPress", "Bench\r\nPress", "Bench\u{85}Press"]
    )
    func lineSeparators_areRefused(_ name: String) {
        let refused = Self.result(name) == .controlCharacter
        if name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            #expect(refused, "a Cc line break is refused today: \(name.unicodeScalars.map(\.value))")
        } else {
            withKnownIssue("S3-3: U+2028 and U+2029 are Zl and Zp, not Cc; the copy says a line break is refused") {
                #expect(refused, "\(name.unicodeScalars.map(\.value))")
            }
        }
    }

    // MARK: S3-4 · grapheme stuffing (nit, pinned)

    @Test("S3-4. Two characters may carry thousands of combining marks: 2–40 bounds graphemes, not storage")
    func combiningMarks_areUnbounded() throws {
        let name = "a" + String(repeating: "\u{301}", count: 1000) + "b" + String(repeating: "\u{308}", count: 1000)
        let built = try CustomExerciseDraft(name: name).exercise(id: Self.id, among: [Self.bench])
        // Pinned as it stands: 2 characters, 2,002 scalars stored as the name and the short name.
        let pinned = built.name.count == 2 && built.name.unicodeScalars.count == 2002 && built.shortName == built.name
        #expect(pinned)
    }

    // MARK: Pins of what holds

    @Test(
        "Pin: case, diacritics and width fold into one key, so each of these is the bench press",
        arguments: ["bench press", "BENCH PRESS", "Bénch Prèss", "Ｂｅｎｃｈ Ｐｒｅｓｓ", "  Bench Press\n", "Be\u{301}nch Press"]
    )
    func foldedNames_areDuplicates(_ name: String) {
        #expect(Self.result(name) == .duplicateName(Self.benchID))
    }

    @Test("Pin: the edited exercise is left out; another with the same key is not")
    func edit_leavesOutItsOwnName() {
        let other = Exercise(
            id: ExerciseID(Fixtures.uuid(7803)), name: "Cable Fly", shortName: "Cable Fly", equipment: .cable,
            primaryMuscle: .chest, pattern: .isolation, defaultStartLoad: [:], isCustom: true
        )
        #expect(Self.result("BENCH press", among: [Self.bench, other], id: Self.benchID) == nil)
        #expect(Self.result("cable fly", among: [Self.bench, other], id: Self.benchID) == .duplicateName(other.id))
    }

    @Test(
        "Pin: length is counted in graphemes (emoji sequences, flags, combining marks, Hangul, Arabic)",
        arguments: [
            ("👨‍👩‍👧‍👦", 1), ("🇫🇷🇩🇪", 2), ("e\u{301}e\u{301}", 2), ("한국", 2), ("ضغط", 3),
            (String(repeating: "💪🏽", count: 40), 40), (String(repeating: "💪🏽", count: 41), 41)
        ]
    )
    func length_isGraphemes(_ name: String, _ count: Int) {
        let error = Self.result(name)
        if CustomExerciseDraft.nameLength.contains(count) {
            #expect(error == nil, "\(name)")
        } else {
            #expect(error == .nameLength(count), "\(name)")
        }
    }

    @Test("Pin: every Cc scalar is refused, C0, DEL and C1 alike", arguments: [0x0, 0x7, 0x1B, 0x7F, 0x80, 0x9F])
    func controls_areRefused(_ value: UInt32) throws {
        let scalar = try #require(Unicode.Scalar(value))
        #expect(Self.result("Row" + String(scalar) + "ing") == .controlCharacter)
    }

    @Test("Pin: the rules run in order: blank, length, control, duplicate, muscles")
    func rules_runInOrder() {
        let tooLongWithControl = String(repeating: "x", count: 20) + "\t" + String(repeating: "x", count: 21)
        #expect(Self.result("x\u{0}") == .controlCharacter)
        #expect(Self.result("\u{0}") == .nameLength(1))
        #expect(Self.result(tooLongWithControl) == .nameLength(42))
        let draft = CustomExerciseDraft(name: "bench press", primaryMuscle: .chest, secondaryMuscles: [.chest])
        #expect(throws: CustomExerciseError.duplicateName(Self.benchID)) {
            try draft.exercise(id: Self.id, among: [Self.bench])
        }
    }

    @Test(
        "Pin: the primary muscle among the secondaries is refused, whichever muscle it is",
        arguments: MuscleGroup.allCases
    )
    func primaryAmongSecondaries_isRefused(_ muscle: MuscleGroup) {
        let draft = CustomExerciseDraft(name: "Landmine Press", primaryMuscle: muscle, secondaryMuscles: [muscle])
        #expect(throws: CustomExerciseError.primaryAmongSecondaries) {
            try draft.exercise(id: Self.id, among: [Self.bench])
        }
    }
}
