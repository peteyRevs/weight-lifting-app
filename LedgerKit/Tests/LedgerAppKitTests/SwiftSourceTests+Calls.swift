import LedgerTestSupport
import Testing

/// `SwiftSource`, what it knows of calls: the argument a literal stands in, the literal that holds another, the
/// code after a literal, and where a name is called.
extension SwiftSourceTests {
    @Test("A literal knows the call argument it stands in: what is called, the label that opens it, its place")
    func argument_isTheCallsArgument() {
        let source = SwiftSource(#"""
        Label(title, systemImage: isLive ? "pause.fill" : "play.fill").accessibilityIdentifier("a")
        environment.logger.log.fault("Seeding failed")
        let view = Text(isStock ? systemName : "Custom")
        let names = ["plain"]
        Button(action: { log("in a closure") })
        Row(titles: ["in", "an array"])
        """#)
        let arguments = source.literals.map(\.argument)
        #expect(arguments[0] == SwiftCallArgument(callee: "Label", label: "systemImage", index: 1))
        #expect(arguments[1] == arguments[0], "the other arm of the ternary stands in the same argument")
        #expect(arguments[2] == SwiftCallArgument(callee: ".accessibilityIdentifier", label: "", index: 0))
        #expect(arguments[3] == SwiftCallArgument(callee: "environment.logger.log.fault", label: "", index: 0))
        #expect(arguments[4] == SwiftCallArgument(callee: "Text", label: "", index: 0), "a ternary's arm is no label")
        #expect(arguments[5] == nil, "an array outside a call stands in no argument")
        #expect(arguments[6] == SwiftCallArgument(callee: "log", label: "", index: 0), "the closure's own call")
        #expect(arguments[7] == SwiftCallArgument(callee: "Row", label: "titles", index: 0))
        #expect(arguments[8] == arguments[7], "an array in an argument is part of it")
    }

    @Test("A literal inside an interpolation names its holder; the code after a literal is its trail")
    func holderAndTrail_areKept() {
        let source = SwiftSource(#"""
        String(
            localized: "Week \(week)",
            bundle: .module,
            locale: locale
        )
        let line = "a \(f("b \(g("c"))")) d"
        """#)
        #expect(source.literals.map(\.text) == ["Week ", "a  d", "b ", "c"])
        #expect(source.literals.map(\.holder) == [nil, nil, 1, 2])
        #expect(source.literals[0].trail == ",bundle:.module,locale:locale)letline=\"\"")
        #expect(source.literals[2].trail == ")", "inside an interpolation, the trail is the expression's own")
        #expect(source.literals[3].trail == ")")
    }

    @Test("A spelling is found in the code however the code is wrapped, with the line it starts on")
    func linesOfCode_readAcrossLineBreaks() {
        let source = SwiftSource("""
        let a = Bundle.module.localizedString(
            forKey: key,
            value: nil
        )
        // localizedString(forKey: "in a comment")
        let b = "localizedString(forKey: in a literal)"
        let c = bundle.localizedString(forKey: other)
        """)
        #expect(source.lines(ofCode: "localizedString(forKey") == [1, 7])
        #expect(source.lines(ofCode: "notThere") == [])
        #expect(source.lines(ofCode: "") == [])
    }

    @Test("A call is found by its name, however it is wrapped, with whether a literal opens it")
    func calls_areFoundByName() {
        let source = SwiftSource(#"""
        let a = Text("Today")
        return Text(title) + SwiftUI.Text(
            "Resume \(timer)", bundle: .module
        )
        let b = richText("x") + Text(verbatim: "y")
        // Text("in a comment")
        let c = "Text(in a literal)"
        func make() -> Text { Text.init(title) }
        """#)
        #expect(source.calls(of: "Text").map(\.line) == [1, 2, 2, 5])
        #expect(source.calls(of: "Text").map(\.opensWithALiteral) == [true, false, true, false])
        #expect(source.calls(of: "richText").map(\.line) == [5])
        #expect(source.calls(of: "NotThere").isEmpty)
    }
}
