import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `CSVExport`'s quoting (N13) and formula guard (N14).
extension CSVExportAdversarialTests {
    // MARK: - Quoting

    @Test(
        "A name holding a comma, a quote, a CR or an LF is quoted with its quotes doubled, and reads back the same",
        arguments: [
            "Bench, paused",
            "Row \"heavy\"",
            "Two\nlines",
            "Car\rriage",
            "Both\r\nends",
            "\"",
            "\"\"",
            ",",
            "Quote then accent \"\u{0301}",
            "Trailing CR\r",
            "x\n"
        ]
    )
    func quoting_readsBack(name: String) throws {
        let text = CSVExport.render(
            workouts: [Self.workout(name: name, tag: name, [(name, [.init(100, 5)])])],
            units: .lb,
            calendar: Fixtures.calendar
        )
        let rows = try #require(Self.read(text), "not RFC 4180 for \(name.debugDescription)")
        let last = try #require(rows.last)
        for column in [2, 3, 4] {
            #expect(Array(last[column]) == Self.scalars(name), "column \(column) of \(name.debugDescription)")
        }
    }

    @Test("A plain name is not quoted")
    func plainName_notQuoted() {
        let line = CSVExport.lines(
            for: Self.workout([("Bench Press", [.init(100, 5)])]),
            units: .lb,
            calendar: Fixtures.calendar
        )
        #expect(line.contains(",Push,A,Bench Press,1,"))
    }

    // MARK: - The formula guard (N14)

    @Test(
        "A text field starting with = + - @ tab or CR gets a leading quote mark, in every text column",
        arguments: ["=HYPERLINK(\"http://x\",\"y\")", "+1", "-1", "@SUM(A1)", "\tcmd", "\rcmd", "=", "-", "@"]
    )
    func formulaGuard_prefixes(name: String) throws {
        let rows = try Self.rows([Self.workout(name: name, tag: name, [(name, [.init(100, 5)])])])
        let last = try #require(rows.last)
        for column in [2, 3, 4] {
            #expect(
                Array(last[column].unicodeScalars) == Self.scalars("'" + name),
                "column \(column) of \(name.debugDescription)"
            )
        }
    }

    @Test("A formula character later in a name, or after a leading space, is left alone", arguments: [
        "Bench=1", "a+b", "Pull-up", "me@home", " =1", "'=1"
    ])
    func formulaGuard_onlyTheFirstScalar(name: String) throws {
        let rows = try Self.rows([Self.workout([(name, [.init(100, 5)])])])
        #expect(rows.last?[4] == name)
    }

    @Test("Numbers are never prefixed: a negative weight and its estimate stay numbers")
    func formulaGuard_neverOnNumbers() throws {
        let rows = try Self.rows([Self.workout([("Assisted dip", [.init(-50, 5), .init(-2.5, 13)])])])
        #expect(rows[1][7] == "-50")
        #expect(rows[1][10].hasPrefix("-"))
        #expect(rows[1][10].first != "'")
        #expect(rows[2][7] == "-2.5")
        #expect(rows.dropFirst().allSatisfy { row in [0, 1, 5, 7, 8, 9, 10].allSatisfy { !row[$0].hasPrefix("'") } })
    }

    @Test("A weight that rounds to zero from below is written 0, never -0")
    func negativeZero_isZero() throws {
        var workout = Self.workout([("Band", [.init(0, 5)])])
        workout.exercises[0].sets[0].weight = .kilograms(Decimal(string: "-0.001") ?? 0)
        let rows = try Self.rows([workout], units: .kg)
        #expect(rows.last?[7] == "0")
    }
}
