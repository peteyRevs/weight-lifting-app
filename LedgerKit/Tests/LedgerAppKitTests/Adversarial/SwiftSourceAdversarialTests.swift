import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: `SwiftSource`, the reader under `CopyAudit`, against Swift's own lexical rules (The
/// Swift Programming Language, "Lexical Structure"): what is a literal, what it says, where it starts, and that no
/// source, however cut short, stops the reader.
@Suite("Adversarial F09 S1 · SwiftSource")
nonisolated struct SwiftSourceAdversarialTests {
    static func texts(_ source: String) -> [String] {
        SwiftSource(source).literals.map(\.text)
    }

    @Test("Escapes are resolved, and a raw literal keeps its backslashes")
    func escapes_areResolved() {
        #expect(Self
            .texts(#"let a = "tab\tquote\"slash\\apostrophe\'nul\0end""#) == ["tab\tquote\"slash\\apostrophe'nul\0end"])
        #expect(Self.texts(#"let a = "\u{1F3CB}\u{E9}\u{2014}""#) == ["\u{1F3CB}\u{E9}\u{2014}"])
        #expect(Self.texts(##"let a = #"a\nb"#"##) == [#"a\nb"#])
        #expect(Self.texts(##"let a = #"a\#nb"#"##) == ["a\nb"])
        #expect(Self.texts(###"let a = ##"a"#b\#(c)"##"###) == [##"a"#b\#(c)"##])
    }

    @Test("Literals come in the order of their opening quotes: one inside an interpolation follows its holder")
    func literals_comeInOrder() {
        let source = SwiftSource(#"let line = "a \(join("b", "\(c) d")) e" + "f""#)
        #expect(source.literals.map(\.text) == ["a  e", "b", " d", "f"])
        let outer = source.literals.first
        #expect(outer?.parts == [.text("a "), .interpolation(#"join("b", "\(c) d")"#), .text(" e")])
    }

    @Test("A literal's line is the line of its opening quote, counted through comments and multi-line literals")
    func line_isTheOpeningQuotes() {
        let text = "/* one\n   two */\nlet a = \"\"\"\n    first\n    \"\"\"\n"
            + "// \"not one\"\nlet b = \"second\"\r\nlet c = \"third\""
        let source = SwiftSource(text)
        #expect(source.literals.map(\.line) == [3, 7, 8])
        #expect(source.literals.map(\.isMultiline) == [true, false, false])
        #expect(source.literals.first?.text.contains("first") == true)
        #expect(source.code.count == 8)
    }

    @Test("The lead is the code before the quote, without comments or whitespace, across a line break")
    func lead_isTheCodeBeforeTheQuote() {
        let source = SwiftSource("view.accessibilityIdentifier( // the title\n    /* id */ \"today.title\"\n)")
        #expect(source.literals.first?.lead.hasSuffix("accessibilityIdentifier(") == true)
        let label = SwiftSource("Label(title, systemImage:\n    \"calendar\")")
        #expect(label.literals.first?.lead.hasSuffix("systemImage:") == true)
    }

    @Test("The code has no comment and no literal's text, and keeps one entry per line")
    func code_hasNoCommentOrLiteralText() {
        let source =
            SwiftSource("let a = \"Start\" // Text(\"x\")\n/* NSLocalizedString */ let b = #\"raw\"#\nlet c = 1")
        #expect(source.code.count == 3)
        let joined = source.code.joined(separator: "\n")
        #expect(!joined.contains("Start") && !joined.contains("Text") && !joined.contains("raw"))
        #expect(!joined.contains("NSLocalizedString"))
        #expect(source.compactCode.contains("leta=\"\""))
        #expect(source.compactCode.hasSuffix("letc=1"))
    }

    @Test("A source cut short anywhere is read to its end: no trap, no endless loop", .timeLimit(.minutes(1)))
    func truncatedSource_isReadToItsEnd() {
        let source = """
        /* a /* nested " */ comment */ let a = "x \\(f("y \\(g(#"z"#))")) w" // tail "
        let b = #"raw \\#(h("i")) \\( "# + \"\"\"
            multi " \\(j) \\\"\"\" \\
            line
            \"\"\"
        let c = ##"a"#b"## /* open
        """
        let characters = Array(source)
        var read = 0
        for end in 0 ... characters.count {
            let prefix = String(characters[..<end])
            let parsed = SwiftSource(prefix)
            #expect(parsed.code.count >= prefix.count { $0 == "\n" })
            read += 1
        }
        #expect(read == characters.count + 1)
    }

    @Test("Random text is read to its end, and so is audited", .timeLimit(.minutes(1)), arguments: 1 ... 200)
    func randomText_isRead(seed: Int) throws {
        var random = AdversarialRandom(seed: seed)
        let alphabet = Array("\"\\#()/*\n \r{}u19aZ:.,+%@")
        let length = Int.random(in: 0 ... 80, using: &random)
        let text = String((0 ..< length).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &random)] })
        let source = SwiftSource(text)
        #expect(source.code.count >= 1 || text.isEmpty, "seed \(seed)")
        let catalog = try AdversarialCatalog.catalog([])
        let sources = ["Views/Screen.swift": text, "FixtureCopy.swift": text]
        _ = CopyAudit(sources: sources, catalog: catalog).findings
    }
}
