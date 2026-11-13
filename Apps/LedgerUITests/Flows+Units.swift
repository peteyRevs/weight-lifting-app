import XCTest

/// F15 S1, criterion 5 as C6 restates it: a finished set converts when the lifter switches to kilograms. With the
/// seed program's four weeks of history (`-LEDGER_UITEST_HISTORY 4`) at noon on Wednesday of its week 5, the newest
/// workout is that Monday's Upper A. Its detail's bench press row reads its sets in pounds; Settings, then KG; Today's
/// volume tile reads kilograms, and the same detail, without a relaunch, reads the same sets in kilograms.
///
/// The kilograms are computed here from the pounds the row read, never copied from a screenshot (question 9, A): a
/// finished workout shows exactly in the current unit (F14 Q1), `Weight.formatted(in:)`. That rule, stated in
/// `kilograms(fromPounds:)`, prints 185 lb as "83.9": the two-decimal "83.91" of the plan is the rounding the rule
/// keeps only for a whole number of quarter kilograms.
extension Flows {
    @MainActor
    func test_unitsSwitch_convertsAFinishedSet() throws {
        let arguments = ["-LEDGER_UITEST_NOW", Self.wednesday, "-LEDGER_UITEST_PROGRAM", "seed"]
        let steps = Steps(launching: arguments + ["-LEDGER_UITEST_HISTORY", "4"], for: self)
        let app = steps.app
        XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(steps.element(saying: "lb moved").waitForExistence(timeout: 10), "a new US install is in pounds")

        app.tabBars.buttons["History"].tap()
        let newest = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10), "History lists the seeded workouts")
        XCTAssertTrue(newest.label.hasPrefix("Upper A"), "the newest is Monday's Upper A: \(newest.label)")
        newest.tap()
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "its detail")
        let bench = steps.element(startingWith: "Barbell Bench Press, ")
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        let chip = try firstChip(of: bench.label)
        let pounds = try weight(in: chip)
        XCTAssertTrue(bench.label.contains(" lb, Logged "), "the row reads in pounds: \(bench.label)")
        steps.attachScreenshot(named: "The workout's detail, in pounds")

        switchToKilograms(steps)
        XCTAssertTrue(steps.element(saying: "kg moved").waitForExistence(timeout: 5), "Today's volume tile")

        app.tabBars.buttons["History"].tap()
        let converted = try chip.replacingOccurrences(of: "\(pounds)×", with: Self.kilograms(fromPounds: pounds) + "×")
        let reads = NSPredicate(format: "label CONTAINS %@", "Logged \(converted)")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reads, object: bench)], timeout: 5),
            .completed,
            "\(bench.label) does not log \(converted)"
        )
        steps.attachScreenshot(named: "The same detail, in kilograms")
        expectTheBenchPressChart(steps)
    }

    /// Today's gear, then KG in Settings, then back to Today.
    @MainActor
    private func switchToKilograms(_ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["Today"].tap()
        app.buttons["Settings"].tap()
        let kilograms = app.buttons["kilograms"]
        XCTAssertTrue(kilograms.waitForExistence(timeout: 5), "Settings")
        kilograms.tap()
        let isSelected = NSPredicate(format: "isSelected == true")
        let selected = XCTNSPredicateExpectation(predicate: isSelected, object: kilograms)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed, "KG is chosen")
        app.navigationBars.buttons["BackButton"].tap()
    }

    /// The seeded weeks reach the exercise's chart too: drawn, and with a value VoiceOver reads (its change).
    @MainActor
    private func expectTheBenchPressChart(_ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["Library"].tap()
        let recent = NSPredicate(format: "label == 'Barbell Bench Press' AND value CONTAINS ' sessions'")
        let row = app.buttons.matching(recent).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the bench press is in RECENTLY LOGGED")
        row.tap()
        let chart = app.otherElements["Estimated 1RM by week"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "the chart is drawn")
        XCTAssertFalse((chart.value as? String ?? "").isEmpty, "the chart reads its change over the weeks")
        steps.attachScreenshot(named: "The bench press's chart over the seeded weeks")
    }

    /// The first chip of a receipt row as VoiceOver reads it: "5 × 200×5" of "Barbell Bench Press, Prescribed 5 × 5 @
    /// 200 lb, Logged 5 × 200×5, 200×4".
    private func firstChip(of label: String) throws -> String {
        let logged = try XCTUnwrap(label.components(separatedBy: ", Logged ").last, label)
        return try XCTUnwrap(logged.components(separatedBy: ", ").first, label)
    }

    /// The weight of a chip, "200" of "5 × 200×5" or of "200×4": what comes before its reps.
    private func weight(in chip: String) throws -> String {
        let parts = chip.components(separatedBy: "×")
        XCTAssertGreaterThanOrEqual(parts.count, 2, "no weight in \(chip)")
        return parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
    }

    /// The Domain's rule for a weight in kilograms (`Weight.shownValue(in:)`): pounds × 0.45359237 exactly, rounded
    /// to hundredths half away from zero; printed so when that is a whole number of quarters (a plate's value), and
    /// to one decimal otherwise, trailing zeros dropped and "." the point. 185 lb is 83.91458845 kg: "83.9". It is
    /// the rule exactly for the weights the seed program's plate steps give; it is not a general converter.
    static func kilograms(fromPounds text: String) throws -> String {
        let pounds = try XCTUnwrap(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), text)
        let kilograms = pounds * Decimal(sign: .plus, exponent: -8, significand: 45_359_237)
        let hundredths = rounded(kilograms, scale: 2)
        let shown = rounded(hundredths * 4, scale: 0) == hundredths * 4 ? hundredths : rounded(kilograms, scale: 1)
        return "\(shown)"
    }

    private static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
