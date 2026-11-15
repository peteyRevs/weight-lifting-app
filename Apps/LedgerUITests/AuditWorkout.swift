import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit on the active workout's cover, three ways
/// (`AuditWay`): the solo card, the swap sheet, the rest panel, the superset block, the finish sheet and the
/// receipt. Each is reached through the Debug menu's sample workout (the seed's Upper A), as the older workout
/// tests reach them. The clock is not moved: `-LEDGER_UITEST_NOW` moves the app's clock but not the header's
/// elapsed time, which counts by the wall clock from a start the moved clock set, so a moved clock draws a time no
/// lifter sees ("1424:17:08"), whose width changes the header's layout at Accessibility XXXL. What the audit reports
/// and is excused is `exclusions`' (measured, in the implementation notes); anything else fails. Nightly only: the
/// `PR` plan selects `Smoke`.
final class AuditWorkout: XCTestCase {
    private static let arguments = ["-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The card as the workout opens, its swap sheet, and the rest a logged set starts.
    @MainActor
    func test_cardSwapSheetAndRestPanel_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions, open: [Self.headerPillsBroken])
        try audit.threeWays(launching: Self.arguments) { steps in
            let app = steps.app
            steps.startSampleWorkout()
            XCTAssertTrue(steps.cardTitle.waitForExistence(timeout: 10))
            try audit.audit(steps, screen: "solo card")

            app.buttons["workout.card.swap"].tap()
            let row = app.buttons["workout.swap.row.0"]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the swap sheet's rows are read")
            try audit.audit(steps, screen: "swap sheet")
            app.buttons["workout.swap.cancel"].tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the sheet went down")

            steps.logSet("1")
            XCTAssertTrue(steps.skip.waitForExistence(timeout: 5), "a logged set starts a rest")
            try audit.audit(steps, screen: "rest panel", pinned: .restPanel(in: app))
            steps.skipRest()
            steps.discard()
        }
    }

    /// The superset block, the finish sheet over a workout with a set logged, and the receipt once it is saved.
    @MainActor
    func test_supersetFinishSheetAndReceipt_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions, open: [Self.headerPillsBroken])
        try audit.threeWays(launching: Self.arguments) { steps in
            let app = steps.app
            steps.startSampleWorkout()
            let lat = app.buttons["workout.remaining.row.3"]
            XCTAssertTrue(lat.waitForExistence(timeout: 10))
            steps.scrollUntilHittable(lat)
            lat.tap()
            XCTAssertTrue(app.staticTexts["workout.block.title"].waitForExistence(timeout: 5), "the superset block")
            try audit.audit(steps, screen: "superset block")

            steps.logSet("A1")
            app.buttons["workout.header.finish"].tap()
            let save = app.buttons["workout.finish.save"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5), "End workout? is up")
            try audit.audit(steps, screen: "finish sheet")
            save.tap()
            XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt shows")
            try audit.audit(steps, screen: "receipt")
            steps.closeReceipt()
        }
    }
}

extension AuditWorkout {
    /// The screens whose header the audit reported "Minimize" on.
    static let headerScreens: Set = ["solo card", "rest panel", "superset block"]

    /// The workout cover's measured exclusions (F15-S2-3 to 9, the implementation notes).
    static var exclusions: [ScreenExclusion] {
        [
            .eyebrows([
                "solo card": ["UPPER A — PUSH FOCUS", "REMAINING", "5 LB", "1 REP"],
                "rest panel": ["UPPER A — PUSH FOCUS", "5 LB", "1 REP"],
                "superset block": ["UPPER A — PUSH FOCUS", "2.5 LB", "1 REP"],
                "receipt": ["TIME", "SETS", "LB MOVED", "LOGGED"]
            ]),
            .shortLines([
                "solo card": ["UPPER A — PUSH FOCUS", "Barbell Bench Press", "5 × 5 @ 180 lb · RPE 8"],
                "rest panel": ["UPPER A — PUSH FOCUS", "Barbell Bench Press", "5 × 5 @ 180 lb · RPE 8"],
                "superset block": ["UPPER A — PUSH FOCUS", "Superset · block 4 of 4"],
                "receipt": ["Upper A — Push focus", "LB MOVED"]
            ]),
            headerPillsWhole,
            .underThePinnedPart(on: ["rest panel"]),
            .accentButtons(["Skip rest", "Save workout"], on: ["rest panel", "finish sheet"]),
            receiptDate,
            receiptDateLine,
            skipRestUnnamed
        ]
    }

    /// F15-S2-7 on "Skip rest" (white on the accent, 3.10:1) when the audit reports it without its element. From
    /// 2026-11-14 13:25 on the rest panel's one "Contrast nearly passed" comes with no element and no frame, in light
    /// and dark at the default size, its detail still naming a `SwiftUI.AccessibilityNode` as the labelled one's
    /// did; the labelled one is gone from the same runs, and the panel holds no other accent control. The runs
    /// before and after differ in neither the frozen clock nor the appearance seam (the notes). Excused once a way
    /// on the rest panel at the default size, and never beside a labelled "Skip rest" near pass.
    static var skipRestUnnamed: ScreenExclusion {
        ScreenExclusion(
            finding: "F15-S2-7",
            issue: "Contrast nearly passed with no element, rest panel",
            perScreenAndWay: 1,
            unlessBeside: { $0.summary == "Contrast nearly passed" && $0.label == "Skip rest" },
            excuses: {
                $0.type == .contrast && $0.summary == "Contrast nearly passed" && $0.screen == "rest panel"
                    && $0.way != .largest && $0.elementType == .any && $0.frame.isNull
                    && $0.detail.contains("SwiftUI.AccessibilityNode")
            }
        )
    }

    /// Whether `label` is the receipt's date as it writes today's ("Saturday, November 14"), no longer than the
    /// longest it writes, "Wednesday, September 30", measured at Accessibility XXXL (the notes).
    static func isDate(_ label: String) -> Bool {
        label.count <= "Wednesday, September 30".count
            && label.range(of: #"^[A-Z][a-z]+day, [A-Z][a-z]+ \d{1,2}$"#, options: .regularExpression) != nil
    }

    /// F15-S2-4 on the receipt's date, a caption on the role's native line: whole in its pictures at both sizes.
    static var receiptDateLine: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on the receipt's date") {
            $0.summary == "Text clipped" && $0.screen == "receipt" && $0.elementType == .staticText && isDate($0.label)
        }
    }

    /// F15-S2-9: the receipt's date (a caption, 12 pt tall) is no control. VoiceOver's
    /// escape, "Done", is set on the receipt's stack, and SwiftUI hands it to each element of it
    /// (`ReceiptTests.escape_isDone` performs it on the first), which the audit takes for a tap target. Of those it
    /// reports the date alone: the pinned header's other two are 29 pt (the name) and 44 pt ("Done") tall. Moving
    /// the action onto a containing element (review S3) took the report away but left the first element without
    /// the escape, which `escape_isDone` caught; so it stays where it is, and this is excused.
    static var receiptDate: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-9", issue: "Hit area too small, the receipt's date") {
            $0.summary == "Hit area is too small" && $0.screen == "receipt" && $0.elementType == .staticText
                && isDate($0.label)
        }
    }

    /// The header's two pills, "Minimize" and "Finish".
    static let headerPills: Set = ["workout.header.minimize", "workout.header.finish"]

    /// F15-S2-4 on the header's "Minimize" and "Finish", the pills' button role: each whole on one line at the
    /// default size (measured in light; the dark way is measured in S2a's second phase). At Accessibility XXXL each
    /// breaks inside the word: `headerPillsBroken`.
    static var headerPillsWhole: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on the header's pills at the default size") {
            $0.summary == "Text clipped" && headerPills.contains($0.identifier) && $0.way != .largest
                && headerScreens.contains($0.screen)
        }
    }

    /// F15-S2-10, open: at Accessibility XXXL "Minimize" is drawn "Minimi / ze" and "Finish" "Finis / h" (the audit
    /// reported "Finish" from S2a's second round on). A real layout finding, an expected failure until the follow-up
    /// PR after S2 lays the header's row out for the accessibility sizes.
    static var headerPillsBroken: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-10", issue: "the header's pills break inside the word at Accessibility XXXL") {
            $0.summary == "Text clipped" && headerPills.contains($0.identifier) && $0.way == .largest
                && headerScreens.contains($0.screen)
        }
    }
}
