import XCTest

extension AuditExclusionsTests {
    private static let under = CGRect(x: 26, y: 702, width: 7, height: 12)
    private static let above = CGRect(x: 26, y: 600, width: 7, height: 12)
    private static let minimize = "workout.header.minimize"

    /// The workout cover's issues as measured.
    private static var workoutExcused: [ScreenIssue] {
        [
            issue("solo card", dynamicType, "REMAINING"),
            issue("solo card", clipped, "Minimize", type: .button, identifier: minimize),
            issue("rest panel", contrast, "5", frame: under, pinned: panel),
            issue("rest panel", contrast, "+ Add set", type: .button, frame: under, pinned: panel),
            issue("finish sheet", nearly, "Save workout", type: .button),
            issue("solo card", clipped, "Finish", type: .button, identifier: "workout.header.finish"),
            issue("receipt", clipped, "Saturday, November 14"),
            issue("receipt", hitArea, "Saturday, November 14"),
            ScreenIssue(screen: "rest panel", type: .contrast, summary: nearly)
        ]
    }

    /// Their near misses.
    private static var workoutNearMisses: [ScreenIssue] {
        [
            issue("receipt", hitArea, "Upper A — Push focus"),
            issue("solo card", clipped, "Saturday, November 14"),
            issue("solo card", dynamicType, "Barbell Bench Press"),
            issue("solo card", clipped, "Finish", type: .button),
            issue("solo card", contrast, "Minimize", type: .button),
            issue("Settings", clipped, "Minimize", type: .button, identifier: minimize),
            issue("solo card", clipped, "Minimize", type: .button, identifier: minimize, way: .largest),
            // A line above the panel's top, one ending in the 7 pt the old 24 pt margin took in, a line over a screen
            // with no panel, what is no text or button, and the panel's own "Skip rest" and status.
            issue("rest panel", contrast, "5", frame: above, pinned: panel),
            issue(
                "rest panel",
                contrast,
                "4",
                frame: CGRect(x: 26, y: 645, width: 7, height: 18),
                pinned: panel
            ),
            issue(
                "rest panel",
                contrast,
                "Skip rest",
                type: .button,
                identifier: "workout.rest.skip",
                frame: CGRect(x: 207, y: 762, width: 163, height: 54),
                pinned: panel,
                inPinnedPart: true
            ),
            issue(
                "rest panel",
                contrast,
                "Resting",
                frame: CGRect(x: 110, y: 690, width: 80, height: 15),
                pinned: panel,
                inPinnedPart: true
            ),
            // An eyebrow and a short line measured on one screen, met on another.
            issue("receipt", clipped, "Barbell Bench Press"),
            issue("solo card", clipped, "Upper A — Push focus"),
            issue("receipt", dynamicType, "REMAINING"),
            issue("solo card", contrast, "5", frame: under),
            issue("rest panel", contrast, "B", type: .other, frame: under, pinned: panel),
            issue("finish sheet", contrast, "Save workout", type: .button),
            issue("finish sheet", nearly, "Discard", type: .button),
            issue("receipt", hitArea, "Done", type: .button),
            issue("solo card", hitArea, "Elapsed time", type: .other),
            issue("receipt", contrast, "Friday, November 13")
        ]
    }

    @MainActor
    func test_workoutExclusions_excuseNothingWider() {
        check(AuditWorkout.exclusions, excused: Self.workoutExcused, nearMisses: Self.workoutNearMisses)
    }

    /// The rest panel's element-less near pass is excused once a way, and nowhere else.
    @MainActor
    func test_unnamedSkipRest_isExcusedOnceAWayOnTheRestPanel() {
        let unnamed = ScreenIssue(screen: "rest panel", type: .contrast, summary: Self.nearly)
        var dark = unnamed
        dark.way = .dark
        let exclusions = AuditWorkout.exclusions
        XCTAssertNotNil(ScreenAudit.exclusion(for: unnamed, in: exclusions, among: [unnamed, dark]))
        XCTAssertNil(ScreenAudit.exclusion(for: unnamed, in: exclusions, among: [unnamed, unnamed]), "a second")
        var elsewhere = unnamed
        elsewhere.screen = "solo card"
        XCTAssertNil(ScreenAudit.exclusion(for: elsewhere, in: exclusions), "another screen")
        elsewhere = unnamed
        elsewhere.summary = Self.contrast
        XCTAssertNil(ScreenAudit.exclusion(for: elsewhere, in: exclusions), "Contrast failed")
    }
}
