import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on the Program tab's Day
/// editor and its exercise-picker sheet (the Library's screens: `AuditLibrary`). On the seed program at noon on
/// Wednesday of its week 5. What the audit reports and is excused is each screen's exclusions' (measured, in the
/// implementation notes); anything else fails. One test per screen, so each stays under about four minutes on a Mac
/// (the plan's R5 and C12; the nightly allows 600 s a test on the runner). Nightly only.
final class AuditProgramLibrary: XCTestCase {
    static let arguments = ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z", "-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lower A's Day editor, from the builder.
    @MainActor
    func test_dayEditor_passesTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.threeWays(launching: Self.arguments) { steps in
            let app = steps.app
            Self.openTheDayEditor(steps)
            try audit.audit(steps, screen: "Day editor")
            audit.reach(steps, screen: "Day editor", [app.buttons["Delete day"], app.buttons[Self.addFromLibrary]])
            audit.expectScrollsClear(steps, screen: "Day editor", anchor: "SUPERSET", last: "Delete day") {
                app.tabBars.firstMatch.frame.minY
            }
        }
    }

    /// The Day editor's "+ Add exercise from library" sheet, light and dark at the default size (`auditThePicker`).
    @MainActor
    func test_exercisePicker_lightAndDark_passesTheAudit() throws {
        try auditThePicker([.light, .dark])
    }

    /// The picker at Accessibility XXXL: a way of its own, as the three would take over four minutes on a Mac.
    @MainActor
    func test_exercisePicker_atAccessibilityXXXL_passesTheAudit() throws {
        try auditThePicker([.largest])
    }

    /// The Day editor's "+ Add exercise from library" sheet; its list for "Press", a few screens long, swiped to its
    /// end: its last row clears the foot.
    @MainActor
    private func auditThePicker(_ ways: [AuditWay]) throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.run(ways, launching: Self.arguments) { steps in
            let app = steps.app
            Self.openTheDayEditor(steps)
            let open = app.buttons[Self.addFromLibrary]
            steps.scrollUntilHittable(open)
            open.tap()
            let search = app.textFields["Search exercises"]
            XCTAssertTrue(search.waitForExistence(timeout: 5), "the exercise picker")
            let foot = PinnedPart.sheetFoot(app.buttons["Select exercises to add"])
            try audit.audit(steps, screen: "exercise picker", pinned: foot)
            audit.reach(steps, screen: "exercise picker", [foot.top, search])
            search.tap()
            search.typeText("Press\n") // the return key puts the keyboard away, and the foot back at the bottom
            audit.expectScrollsClear(steps, screen: "exercise picker", anchor: "Arnold Press", last: Self.lastPress) {
                foot.minY
            }
        }
    }

    /// The builder, then Lower A's card: its Day editor.
    @MainActor
    static func openTheDayEditor(_ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10), "the builder")
        let card = app.buttons["Lower A — Squat focus"].firstMatch
        steps.scrollUntilHittable(card)
        card.tap()
        XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the Day editor")
    }
}

extension AuditProgramLibrary {
    /// The last row of the picker's list for "Press": the list's end. (The history's end is its oldest session.)
    static let lastPress = "Smith Machine Overhead Press"

    /// The Day editor's way to the picker.
    static let addFromLibrary = "+ Add exercise from library"

    /// The measured exclusions of the Day editor, its picker and the Library's screens (F15-S2-3 to 8, the notes).
    static var exclusions: [ScreenExclusion] {
        let fields: Set = ["NAME", "EQUIPMENT", "PRIMARY MUSCLE", "MOVEMENT PATTERN", "SECONDARY MUSCLES"]
        let fieldLines: Set = ["PRIMARY MUSCLE", "MOVEMENT PATTERN", "SECONDARY MUSCLES"]
        return [
            .eyebrows([
                "Day editor": ["DAY 2 OF 4", "SUPERSET"],
                "New exercise": fields,
                "Edit exercise": fields,
                "exercise history": ["ESTIMATED 1RM · 8 WEEKS", "SESSION LOG"]
            ]),
            // "Day name" is the day's name field, drawn in the title role (1.0 line). Its frame is the field's; the
            // name is drawn under it as wrapping text, whole in the screen's picture at both sizes (at XXXL the
            // field's own picture cuts the second line's tails, which the screen shows whole).
            .shortLines([
                "Day editor": ["+ Add exercise from library", "2 exercises back to back · rest after B", "Day name"],
                "exercise picker": ["Select exercises to add"],
                "New exercise": fieldLines,
                "Edit exercise": fieldLines,
                "exercise history": ["Barbell Bench Press", "ESTIMATED 1RM · 8 WEEKS"]
            ]),
            .underTheTabBar(on: ["Day editor", "exercise history"]),
            .underThePinnedPart(on: ["exercise picker"]),
            .accentButtons(["Save"], on: ["New exercise", "Edit exercise"]),
            wholeName
        ]
    }

    /// F15-S2-4 on Edit exercise's name field (its label is empty, so by identifier): "Landmine Squeeze Press" is
    /// drawn whole in the field's picture in every way, on one line at the default size and on two at Accessibility
    /// XXXL, where the name wraps under the field since S2b (F15-S2-11, fixed); the field's own one-line text, which
    /// is not shown, is what the audit measures. Guards that what is drawn is the whole name, and the field's own line
    /// stays unseen: `CreateExerciseLayoutTests.name_longerThanItsLine_isDrawnWhole` and the reference
    /// `CreateExerciseSnapshotTests.longName_accessibility5_matchesReference` (FeatureLibraryTests, PR lane).
    static var wholeName: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on the whole name, Edit exercise") {
            $0.summary == "Text clipped" && $0.identifier == "library.create.name" && $0.screen == "Edit exercise"
        }
    }
}
