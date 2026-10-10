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

    @Test("The scan reads the twenty-two view files")
    func scan_readsEveryView() throws {
        // S10 added the Day editor's eight: fourteen before.
        let names = try Self.views().map(\.name)
        #expect(names.count == 22, "\(names)")
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
            "DayEditorHeader.swift: send(.rename(text, day: model.id))",
            "DayEditorHeader.swift: send(header.back.action)",
            "DayEditorHeader.swift: send(header.done.action)",
            "DayEditorPage.swift: send(confirmation.confirm.action)",
            "ExercisePickerPage.swift: send(empty.clear.action)",
            "ExercisePickerRow.swift: send(row.action)",
            "ExercisePickerScreen.swift: send(.setQuery($0))",
            "ExercisePickerScreen.swift: send(action)",
            "ExercisePickerScreen.swift: send(model.cancel.action)",
            "ExerciseRow.swift: send(row.action)",
            "FilterChips.swift: send(chip.action)",
            "ProgramHeader.swift: send(.rename(text))",
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

    @Test("The only state a view keeps is the name field's draft and the two fields' focus")
    func views_keepNoStateButTheDraft() throws {
        let kept = try Self.matches(#"@(State|FocusState|Binding|Bindable|StateObject|ObservedObject|AppStorage)\b.*"#)
        #expect(kept == [
            // S10: the day's name has its draft and focus as the program's has, and "Delete day" its alert.
            "DayEditorHeader.swift: @State private var draft: String",
            "DayEditorHeader.swift: @FocusState private var isEditing: Bool",
            "DayEditorPage.swift: @State private var isConfirming = false",
            "ExercisePickerScreen.swift: @FocusState private var isEditing: Bool",
            "ProgramHeader.swift: @State private var draft: String",
            "ProgramHeader.swift: @FocusState private var isEditing: Bool"
        ], "\(kept)")
        let watched = try Self.matches(#"\.(onChange|onReceive|onAppear|onDisappear|onSubmit|task|refreshable)\b"#)
        // S10: the day's name field watches what the program's does.
        let headers = ["DayEditorHeader.swift", "ProgramHeader.swift"]
        #expect(watched == headers.flatMap { Array(repeating: "\($0): .onChange", count: 3) }, "\(watched)")
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
        let found = try Self.matches(pattern)
        #expect(found == [], "\(found)")
    }

    @Test("A view asks a list only whether it is empty, twice: a program's days and a day's short names")
    func views_conditionsOnLists_areTheTwo() throws {
        let asked = try Self.matches(#"[\w.]+\.isEmpty"#)
        #expect(asked == ["DayCard.swift: model.chips.isEmpty", "TrainingDaysSection.swift: model.cards.isEmpty"])
    }

    /// For the orchestrator: criterion 9 is "no rule of its own". The views hold two measures that are no
    /// token: the least width of a day's tag in ems (`DayCard.tagEms`, 3.5) and the strip cell's one line.
    /// Pinned here so that a third is a changed list; whether 3.5 belongs in `LedgerDesign` is a question in
    /// the notes.
    @Test("The only numbers but 0 in the views are the tag's width in ems and the strip cell's one line")
    func views_numbers_areTheTwo() throws {
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
