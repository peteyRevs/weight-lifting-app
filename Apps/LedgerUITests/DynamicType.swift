import XCTest

/// F15 S2b, criterion 7: the iPhone screens of product-spec §2.2 at `accessibility5` (Accessibility XXXL), through
/// the launch argument `-UIPreferredContentSizeCategoryName`, which sets the app's text size for that launch only
/// (never the simulator's own setting, which other lanes share). On each screen one picture is kept, each primary
/// action is scrolled to and can be tapped, and the system's audit finds no clipped text but for the screen's
/// measured exclusions.
///
/// Only what no other test does at that size is here (S2b ruling):
/// - S2a's audits already audit every type, `.textClipped` too, at Accessibility XXXL on the workout's screens, the
///   Day editor and its picker, the exercise history, New and Edit exercise, the workout detail and its edit sheet,
///   Settings and Bar and plates; their walks picture each screen and reach its primary actions in that way
///   (`ScreenAudit.reach`).
/// - Onboarding (`OnboardingAdversarial`, every step audited at the largest size, its pinned button tapped on each)
///   and the Library root (`LibraryAuditAdversarial`, audited at three sizes, its last row scrolled clear) are
///   audited at Accessibility XXXL already; here their primary actions are reached.
/// - So the clip audit runs on Today (a session day, a rest day and its off-schedule sheet), the Program builder and
///   the History list. Nightly only.
final class DynamicType: XCTestCase {
    private static let arguments = ["-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Today on Wednesday of the seed's week 5, with four weeks of history; the Program, Library and History tabs.
    @MainActor
    func test_todayBuilderLibraryAndHistory_atAccessibilityXXXL() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        let wednesday = Self.arguments + ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z", "-LEDGER_UITEST_HISTORY", "4"]
        try audit.run([.largest], launching: wednesday) { steps in
            let app = steps.app
            try audit.audit(steps, screen: "Today", types: .textClipped)
            audit.reach(steps, screen: "Today", [app.buttons["Settings"], app.buttons["Start workout"]])

            app.tabBars.buttons["Program"].tap()
            XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10), "the builder")
            try audit.audit(steps, screen: "Program builder", types: .textClipped)
            audit.reach(steps, screen: "Program builder", [app.buttons["+ Add training day"]])

            app.tabBars.buttons["Library"].tap()
            let search = app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Search '")).firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10), "the Library")
            audit.reach(steps, screen: "Library", [app.buttons["New exercise"].firstMatch, search])

            app.tabBars.buttons["History"].tap()
            let newest = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
            XCTAssertTrue(newest.waitForExistence(timeout: 10), "History lists the seeded workouts")
            try audit.audit(steps, screen: "History", types: .textClipped)
            audit.reach(steps, screen: "History", [newest])
        }
    }

    /// Today on Thursday of week 5, a rest day, and its "Train off-schedule" sheet.
    @MainActor
    func test_restDayAndOffScheduleSheet_atAccessibilityXXXL() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.run([.largest], launching: Self.arguments + ["-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z"]) { steps in
            let app = steps.app
            let offSchedule = app.buttons["Train off-schedule"]
            XCTAssertTrue(offSchedule.waitForExistence(timeout: 10), "a rest day")
            try audit.audit(steps, screen: "Today, rest day", types: .textClipped)
            audit.reach(steps, screen: "Today, rest day", [app.buttons["Settings"], offSchedule])

            offSchedule.tap()
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "the off-schedule sheet")
            try audit.audit(steps, screen: "off-schedule sheet", types: .textClipped)
            let lowerB = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lower B — '")).firstMatch
            audit.reach(steps, screen: "off-schedule sheet", [cancel, lowerB])
        }
    }
}

extension DynamicType {
    /// The measured exclusions of the screens audited here (the implementation notes, S2b): F15-S2-4, texts in
    /// the caption, eyebrow, heading and title roles whose frame is the role's native line. Every glyph of each is
    /// whole in the screen's picture at Accessibility XXXL, and each wraps between words.
    static var exclusions: [ScreenExclusion] {
        [
            .shortLines([
                "Today": ["Wednesday, September 16", "Week 5 of 8 · ~38 min", "Lower A — Squat focus"],
                "Today, rest day": ["Thursday, September 17", "SCHEDULED REST", "No session today"],
                "Program builder": ["BLOCK · 8 WEEKS"]
            ])
        ]
    }
}
