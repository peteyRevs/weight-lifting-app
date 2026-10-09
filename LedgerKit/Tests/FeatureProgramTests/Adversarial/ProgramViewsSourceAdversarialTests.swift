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

    /// Each match of `pattern` in the views' code, as "File.swift: match".
    static func matches(_ pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return try views().flatMap { name, source in
            source.code.flatMap { line in
                regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
                    Range(match.range, in: line).map { "\(name): \(line[$0])" }
                }
            }
        }
    }

    @Test("The scan reads the fourteen view files")
    func scan_readsEveryView() throws {
        let names = try Self.views().map(\.name)
        #expect(names.count == 14, "\(names)")
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
            "ExercisePickerPage.swift: send(empty.clear.action)",
            "ExercisePickerRow.swift: send(row.action)",
            "ExercisePickerScreen.swift: send(.setQuery($0))",
            "ExercisePickerScreen.swift: send(action)",
            "ExercisePickerScreen.swift: send(model.cancel.action)",
            "FilterChips.swift: send(chip.action)",
            "ProgramHeader.swift: send(.rename(text))",
            "ScheduleStrip.swift: send(action)",
            "WeekChips.swift: send(chip.action)",
            "WeekSection.swift: send(action)",
            "WeekSection.swift: send(model.deload.action)"
        ], "\(sent)")
        // The three bare `action`s are unwrapped from the model in the line that sends them.
        let unwrapped = try Self.matches(#"if let action( = (cell|control|model)\.action)? \{"#)
        #expect(unwrapped.count == 3, "\(unwrapped)")
    }

    @Test("The only state a view keeps is the name field's draft and the two fields' focus")
    func views_keepNoStateButTheDraft() throws {
        let kept = try Self.matches(#"@(State|FocusState|Binding|Bindable|StateObject|ObservedObject|AppStorage)\b.*"#)
        #expect(kept == [
            "ExercisePickerScreen.swift: @FocusState private var isEditing: Bool",
            "ProgramHeader.swift: @State private var draft: String",
            "ProgramHeader.swift: @FocusState private var isEditing: Bool"
        ], "\(kept)")
        let watched = try Self.matches(#"\.(onChange|onReceive|onAppear|onDisappear|onSubmit|task|refreshable)\b"#)
        #expect(watched == Array(repeating: "ProgramHeader.swift: .onChange", count: 3), "\(watched)")
    }

    @Test("The only thing a view reads from its environment is the text size")
    func views_readOnlyTheTextSize() throws {
        let read = try Self.matches(#"@Environment\([^)]*\)"#)
        #expect(
            Set(read.map { String($0.split(separator: ": ")[1]) }) == [#"@Environment(\.dynamicTypeSize)"#],
            "\(read)"
        )
        #expect(read.count == 2, "\(read)")
    }

    static let reachedFor = [
        #"\bTask\b"#, #"\bDispatchQueue\b"#, #"\bTimer\b"#, #"\bTimelineView\b"#, #"\bNotificationCenter\b"#,
        #"\bUserDefaults\b"#, #"\bBundle\b"#, #"\bProcessInfo\b"#, #"\bUIScreen\b"#, #"\bUIDevice\b"#,
        #"\bGeometryReader\b"#, #"\bwithAnimation\b"#, #"\.animation\("#, #"\.transition\("#,
        #"\.(uppercased|lowercased|capitalized|localizedUppercase|localizedCapitalized)\b"#, #"\.rawValue\b"#,
        #"\bString\("#, #"\bInt\("#, #"\.(count|first|last|prefix|suffix|dropFirst|dropLast|reversed|joined)\b"#,
        #"\.(contains|allSatisfy|reduce|compactMap|flatMap|min|max)\("#, #"\b(NumberFormatter|Measurement)\b"#,
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
        #expect(numbers == ["DayCard.swift: 3.5", "ScheduleStrip.swift: 1"], "\(numbers)")
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
