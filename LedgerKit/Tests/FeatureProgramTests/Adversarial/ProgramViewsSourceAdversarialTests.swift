import Foundation
import LedgerTestSupport
import Testing

/// F11 S9, gate G2, round 1: the views' sources, read here (criteria 1 and 9). `ProgramViewsSourceTests` bans
/// a list of spellings; these list what the views do hold instead (every action sent, every piece of state,
/// every condition on a collection, every number), so that a view that begins to decide is a changed list.
@Suite("Adversarial F11 S9 · the views' sources", .tags(.feature))
nonisolated struct ProgramViewsSourceAdversarialTests {
    /// The view files but the previews, by name, with their code: comments gone, every literal as `""`.
    static func views() throws -> [(name: String, source: SwiftSource)] {
        let sources = try CopyAudit.sources(ofModule: "FeatureProgram")
        let views = sources.filter { $0.key.hasPrefix("Views/") && !$0.key.hasSuffix("+Previews.swift") }
        return views.sorted { $0.key < $1.key }
            .map { (String($0.key.dropFirst("Views/".count)), SwiftSource($0.value)) }
    }

    /// Which lines of a file's code stand inside a `Layout` type (`struct EqualCells: Layout { … }`), by its
    /// braces. A layout is arithmetic on its children's sizes: it may count them and take the largest, which
    /// a view that draws a model may not (round 2: the bans below made `EqualCells` add up in loops what
    /// `count` and `max` say plainly, and protected nothing there).
    static func isInsideALayout(_ code: [String]) -> [Bool] {
        var depth = 0
        var isInside = false
        return code.map { line in
            if !isInside, line.range(of: #"\bstruct \w+: Layout \{"#, options: .regularExpression) != nil {
                isInside = true
                depth = 0
            }
            let wasInside = isInside
            if isInside {
                depth += line.count(where: { $0 == "{" }) - line.count(where: { $0 == "}" })
                isInside = depth > 0
            }
            return wasInside
        }
    }

    /// Each match of `pattern` in the views' code, as "File.swift: match"; `outsideLayouts` leaves the lines
    /// of a `Layout` type out.
    static func matches(_ pattern: String, outsideLayouts: Bool = false) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return try views().flatMap { name, source in
            zip(source.code, isInsideALayout(source.code)).flatMap { line, isLayout -> [String] in
                guard !(outsideLayouts && isLayout) else {
                    return []
                }
                return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
                    Range(match.range, in: line).map { "\(name): \(line[$0])" }
                }
            }
        }
    }

    @Test("The scan reads the twenty-four view files")
    func scan_readsEveryView() throws {
        // S10 added the Day editor's eight: fourteen before. Its fix round 1 added `DayEditorBar` (ruling 14)
        // and `NameField` (ruling 16).
        let names = try Self.views().map(\.name)
        #expect(names.count == 24, "\(names)")
    }

    @Test("No view holds a string literal: every text on screen is a string of a model")
    func views_holdNoLiteral() throws {
        let literals = try Self.views().flatMap { name, source in
            source.literals.map { "\(name):\($0.line)" }
        }
        #expect(literals == [])
        #expect(try Self.matches(#"LocalizedStringKey|NSLocalizedString|localized:|\bverbatim:"#) == [])
    }

    @Test("Every action a view sends is a value of its model, but the two a field types")
    func views_sendOnlyTheModelsActions() throws {
        let sent = try Self.matches(#"\bsend\([^()]*(\([^()]*\))?\)"#).sorted()
        #expect(sent == [
            "BlockSection.swift: send(model.addWeek)",
            "BlockSection.swift: send(model.addWeek)",
            "BlockSection.swift: send(model.removeWeek)",
            "BlockSection.swift: send(model.removeWeek)",
            "DayCard.swift: send(model.action)",
            // S10, the Day editor: the name field's `rename` is the one action a view of it makes.
            // Fix round 1: the two buttons are `DayEditorBar`'s (ruling 14), and the name's text reaches the
            // header as `NameField`'s argument (ruling 16).
            "DayEditorBar.swift: send(model.back.action)",
            "DayEditorBar.swift: send(model.done.action)",
            "DayEditorHeader.swift: send(.rename($0, day: model.id))",
            "DayEditorPage.swift: send(confirmation.confirm.action)",
            "ExercisePickerPage.swift: send(empty.clear.action)",
            "ExercisePickerRow.swift: send(row.action)",
            "ExercisePickerScreen.swift: send(.setQuery($0))",
            "ExercisePickerScreen.swift: send(action)",
            "ExercisePickerScreen.swift: send(model.cancel.action)",
            "ExerciseRow.swift: send(row.action)",
            "FilterChips.swift: send(chip.action)",
            // The chore of 2026-10-13: the program's name reaches its header as `NameField`'s argument too.
            "ProgramHeader.swift: send(.rename($0))",
            "ProgressionChips.swift: send(action)",
            "ScheduleStrip.swift: send(action)",
            "SlotDetails.swift: send(field.decrement)",
            "SlotDetails.swift: send(field.increment)",
            "SlotDetails.swift: send(model.action)",
            "WeekChips.swift: send(chip.action)",
            "WeekSection.swift: send(action)",
            "WeekSection.swift: send(model.deload.action)"
        ], "\(sent)")
        // The bare `action`s are unwrapped from the model in the line that sends them. S10, gate G2: four,
        // not three. `ProgressionChips` sends a fourth bare `action`, which the pattern did not count while
        // the count stayed at 3: its unwrapping, from the chip of the model, is pinned with the others.
        let unwrapped = try Self.matches(#"if let action( = (cell|chip|control|model)\.action)? \{"#)
        #expect(unwrapped.count == 4, "\(unwrapped)")
        #expect(sent.count { $0.hasSuffix(": send(action)") } == unwrapped.count, "a bare action, not unwrapped")
    }

    @Test("The only state a view keeps: the name field's draft, the two fields' focus, the delete alert's flag")
    func views_keepNoStateButDraftsFocusAndTheAlert() throws {
        let kept = try Self.matches(#"@(State|FocusState|Binding|Bindable|StateObject|ObservedObject|AppStorage)\b.*"#)
        #expect(kept == [
            // S10: the day's name has its draft and focus as the program's has, and "Delete day" its alert.
            // Fix round 1 (ruling 16): the day's draft and focus are `NameField`'s.
            "DayEditorPage.swift: @State private var isConfirming = false",
            // Sanctioned edit (F12 S1, ruling R5): the search field's focus moved with the field into
            // `LedgerDesign`'s `SearchField`.
            // The chore of 2026-10-13: the program's draft and focus are `NameField`'s too.
            "NameField.swift: @State private var draft: String",
            "NameField.swift: @FocusState private var isEditing: Bool"
        ], "\(kept)")
        let watched = try Self.matches(#"\.(onChange|onReceive|onAppear|onDisappear|onSubmit|task|refreshable)\b"#)
        // S10: the day's name field watches what the program's does.
        // Fix round 1 (ruling 16): `NameField` watches for the day's name.
        // The chore of 2026-10-13: and for the program's, so it alone watches.
        #expect(watched == Array(repeating: "NameField.swift: .onChange", count: 3), "\(watched)")
    }

    @Test("The only thing a view reads from its environment is the text size")
    func views_readOnlyTheTextSize() throws {
        let read = try Self.matches(#"@Environment\([^)]*\)"#)
        #expect(
            Set(read.map { String($0.split(separator: ": ")[1]) }) == [#"@Environment(\.dynamicTypeSize)"#],
            "\(read)"
        )
        // S10: `DayTag`, taken out of `DayCard` for the Day editor's header, and `ExerciseRow`; two before.
        #expect(read.count == 4, "\(read)")
    }

    static let reachedFor = [
        #"\bTask\b"#, #"\bDispatchQueue\b"#, #"\bTimer\b"#, #"\bTimelineView\b"#, #"\bNotificationCenter\b"#,
        #"\bUserDefaults\b"#, #"\bBundle\b"#, #"\bProcessInfo\b"#, #"\bUIScreen\b"#, #"\bUIDevice\b"#,
        #"\bGeometryReader\b"#, #"\bwithAnimation\b"#, #"\.animation\("#, #"\.transition\("#,
        #"\.(uppercased|lowercased|capitalized|localizedUppercase|localizedCapitalized)\b"#, #"\.rawValue\b"#,
        #"\bString\("#, #"\bInt\("#, #"\.(prefix|suffix|dropFirst|dropLast|reversed|joined)\b"#,
        #"\.(contains|allSatisfy|compactMap|flatMap)\("#, #"\b(NumberFormatter|Measurement)\b"#,
        #"\b(UIColor|UIFont)\b"#, #"\bColor\("#, #"\.(font|system|opacity|fontWeight|tracking|kerning)\("#,
        #"\.minimumScaleFactor\("#, #"\.(white|black|gray|red|orange|primary|secondary)\b"#
    ]

    @Test(
        "No view counts, picks from or joins a list, changes a text's case, draws a raw colour or font, or waits",
        arguments: reachedFor
    )
    func views_reachForNothing(_ pattern: String) throws {
        // Sanctioned edit (S14, Pete's question 5, A): the name field asks whether its own draft is only spaces,
        // to show the placeholder over it. The draft is the view's state (S9 ruling 14); no model holds it.
        let found = try Self.matches(pattern).filter { $0 != "NameField.swift: .allSatisfy(" }
        #expect(found == [], "\(found)")
    }

    @Test("A view asks a list only whether it is empty: a program's days, a day's short names, a name's draft")
    func views_conditionsOnLists_areTheTwo() throws {
        let asked = try Self.matches(#"[\w.]+\.isEmpty"#)
        // Sanctioned edit (S14, Pete's question 5, A): and the name field, of its own draft.
        #expect(asked == [
            "DayCard.swift: model.chips.isEmpty", "NameField.swift: draft.isEmpty",
            "TrainingDaysSection.swift: model.cards.isEmpty"
        ])
    }

    /// For the orchestrator: criterion 9 is "no rule of its own". The views hold two measures that are no
    /// token: the least width of a day's tag in ems (`DayCard.tagEms`, 3.5) and the strip cell's one line.
    /// Pinned here so that a third is a changed list; whether 3.5 belongs in `LedgerDesign` is a question in
    /// the notes.
    @Test("The only numbers but 0 in the views: the tag's ems, the caret's quarter turn twice, the strip cell's line")
    func views_numbers_areThePinnedFour() throws {
        let numbers = try Self.matches(#"(?<![\w.])(?!0\b)\d+(\.\d+)?\b"#)
        // S10: a row's caret is the design system's chevron turned a quarter, down or up.
        #expect(
            numbers == [
                "DayCard.swift: 3.5",
                "ExerciseRow.swift: 90",
                "ExerciseRow.swift: 90",
                "ScheduleStrip.swift: 1"
            ],
            "\(numbers)"
        )
    }

    @Test("The previews file is wholly inside #if DEBUG, and its only literals are names and its long name")
    func previews_areDebugOnly() throws {
        let text = try #require(CopyAudit.sources(ofModule: "FeatureProgram")["Views/Program+Previews.swift"])
        let code = SwiftSource(text).code.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(code.first == "#if DEBUG" && code.last == "#endif")
        #expect(code.count { $0.hasPrefix("#if") || $0.hasPrefix("#else") } == 1)
        #expect(!code.contains { $0.contains("ProgramCopy.") && !$0.contains("ProgramCopy.newDay") })
    }
}

// MARK: - Layout types (round 2)

nonisolated extension ProgramViewsSourceAdversarialTests {
    /// What a view may not do to a list of its model, and a layout may do to its children's sizes.
    static let countedOrPicked = [#"\.(count|first|last)\b"#, #"\.(reduce|min|max)\("#, #"\b(min|max)\("#]

    @Test(
        "No view counts a list of its model or picks from one; a layout type may, of its children",
        arguments: countedOrPicked
    )
    func views_countNothing_outsideALayout(_ pattern: String) throws {
        let found = try Self.matches(pattern, outsideLayouts: true)
        #expect(found == [], "\(found)")
    }

    @Test("The scan knows the strip's layout from the views around it")
    func scan_findsTheLayout() throws {
        let strip = try #require(Self.views().first { $0.name == "ScheduleStrip.swift" }).source.code
        let inside = Self.isInsideALayout(strip)
        let first = try #require(inside.firstIndex(of: true))
        #expect(strip[first].contains("struct EqualCells: Layout"))
        #expect(inside.count { $0 } > 40 && !inside[..<first].contains(true))
        let sample = [
            "struct Row: View {",
            "    let rows = model.count",
            "}",
            "struct Grid: Layout {",
            "    func f() { g { 1 } }",
            "}",
            "let x = 1"
        ]
        #expect(Self.isInsideALayout(sample) == [false, false, false, true, true, true, false])
    }
}

// MARK: - S10, gate G2, round 2: the name field

nonisolated extension ProgramViewsSourceAdversarialTests {
    /// The day's `rename` is built in `DayEditorHeader` from what `NameField` hands it, so the one place
    /// `NameField` hands a name over is pinned too: once, with the text as typed.
    @Test("The name field hands a name over in one place, as typed")
    func nameField_handsTheNameOverOnce() throws {
        let handed = try Self.matches(#"\bonRename\([^)]*\)"#)
        #expect(handed == ["NameField.swift: onRename(text)"], "\(handed)")
    }

    /// `NameField` hides whichever of its two texts is not shown with `Color.clear`, a colour that is no
    /// token and that the bans of `reachedFor` do not name. Pinned so that a third is a changed list: one
    /// for the text, one for the field.
    @Test("The only colour a view spells outside the tokens is clear, twice, in the name field")
    func views_spellNoColourButClear() throws {
        let spelled = try Self.matches(#"\bColor\.\w+"#)
        #expect(spelled == ["NameField.swift: Color.clear", "NameField.swift: Color.clear"], "\(spelled)")
    }
}
