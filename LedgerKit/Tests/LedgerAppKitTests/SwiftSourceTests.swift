import LedgerTestSupport
import Testing

/// `SwiftSource` (LedgerTestSupport): the reader under `CopyAudit`. It has to tell code from comments, find every
/// string literal with what stands before it, and walk interpolations.
@Suite("SwiftSource")
struct SwiftSourceTests {
    @Test("Each literal is found with its text, its line and the code before it")
    func literals_carryTextLineAndLead() {
        let source = SwiftSource("""
        Text(title)
            .accessibilityIdentifier("today.title")
        EmptyState("No session", body: "Nothing scheduled")
        """)
        #expect(source.literals.map(\.text) == ["today.title", "No session", "Nothing scheduled"])
        #expect(source.literals.map(\.line) == [2, 3, 3])
        #expect(source.literals[0].lead.hasSuffix(".accessibilityIdentifier("))
        #expect(source.literals[1].lead.hasSuffix("EmptyState("))
        #expect(source.literals[2].lead.hasSuffix("EmptyState(\"\",body:"))
    }

    @Test("A wrapped argument keeps the lead of the call it belongs to")
    func wrappedArgument_keepsItsLead() {
        let source = SwiftSource("""
        String(
            localized: "Can't open your data right now",
            bundle: .module
        )
        """)
        #expect(source.literals.map(\.lead) == ["String(localized:"])
        #expect(source.literals.map(\.line) == [2])
        #expect(source.compactCode == "String(localized:\"\",bundle:.module)")
    }

    @Test("Comments are not code: a quote in one starts no literal, and a comment mark in a literal ends nothing")
    func comments_areNotCode() {
        let source = SwiftSource("""
        // Text("in a line comment")
        /* Text("in a block") /* and "nested" */ still "a comment" */
        let link = "https://example.com/a" // trailing "comment"
        /// A doc comment that says "Today".
        let other = "/* not a comment */"
        """)
        #expect(source.literals.map(\.text) == ["https://example.com/a", "/* not a comment */"])
        #expect(source.literals.map(\.line) == [3, 5])
        #expect(source.code == ["", "", "let link = \"\" ", "", "let other = \"\""])
    }

    @Test("An interpolation's expression is kept and the literals inside it are found; its code is not the line's")
    func interpolation_isKeptApartFromTheLinesCode() {
        let source = SwiftSource(#"""
        let a = "Week \(week) of \(total)"
        let b = "\(isDone ? "Done" : "Pending") · \(names.joined(separator: ", "))"
        """#)
        #expect(source.literals[0].parts == [
            .text("Week "),
            .interpolation("week"),
            .text(" of "),
            .interpolation("total")
        ])
        #expect(source.literals[0].text == "Week  of ")
        #expect(source.literals.map(\.text) == ["Week  of ", " · ", "Done", "Pending", ", "])
        #expect(source.literals[1].parts.first == .interpolation(#"isDone ? "Done" : "Pending""#))
        #expect(source.literals[4].lead.hasSuffix("names.joined(separator:"))
        #expect(source.code == ["let a = \"\"", "let b = \"\""])
    }

    @Test("Escapes are resolved to the text they stand for")
    func escapes_areResolved() {
        let source = SwiftSource(#"""
        let a = "Can\'t \"open\" \\ it\n\tnow\u{2026}"
        let b = ""
        """#)
        #expect(source.literals.map(\.text) == ["Can't \"open\" \\ it\n\tnow…", ""])
    }

    @Test("Multi-line and raw literals are read whole, and the lines after them keep their numbers")
    func multilineAndRawLiterals_areReadWhole() {
        let source = SwiftSource(##"""
        let a = """
            First "line"
            second \(count)
            """
        let b = #"raw "quoted" \n and \#(name)"#
        let c = "after"
        """##)
        #expect(source.literals.map(\.isMultiline) == [true, false, false])
        #expect(source.literals[0].parts.contains(.interpolation("count")))
        #expect(source.literals[0].text.contains("First \"line\""))
        #expect(source.literals[1].parts == [.text(#"raw "quoted" \n and "#), .interpolation("name")])
        #expect(source.literals.map(\.line) == [1, 5, 6])
    }

    @Test("A literal left open ends with its line")
    func unterminatedLiteral_endsWithItsLine() {
        let source = SwiftSource("let a = \"open\nlet b = \"closed\"")
        #expect(source.literals.map(\.text) == ["open", "closed"])
        #expect(source.literals.map(\.line) == [1, 2])
    }

    @Test("A preprocessor line and a macro are code, not a raw literal")
    func hashWithoutAQuote_isCode() {
        let source = SwiftSource("""
        #if DEBUG
        #Preview("Tabs") { content }
        #endif
        """)
        #expect(source.literals.map(\.text) == ["Tabs"])
        #expect(source.literals[0].lead.hasSuffix("#Preview("))
    }
}
