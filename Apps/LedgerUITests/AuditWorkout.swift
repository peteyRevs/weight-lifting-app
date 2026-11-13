import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit on the active workout's cover, three ways
/// (`AuditWay`): the solo card, the swap sheet, the rest panel, the superset block, the finish sheet and the
/// receipt. Each is reached through the Debug menu's sample workout (the seed's Upper A), as the older workout
/// tests reach them. What the audit reports and is excused is `exclusions`' (measured, in the implementation notes);
/// anything else fails. Nightly only: the `PR` plan selects `Smoke`.
final class AuditWorkout: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The card as the workout opens, its swap sheet, and the rest a logged set starts.
    @MainActor
    func test_cardSwapSheetAndRestPanel_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions, open: [Self.minimizeBroken])
        try audit.threeWays(launching: ["-LEDGER_UITEST_PROGRAM", "seed"]) { steps in
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
            let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
            try audit.audit(steps, screen: "rest panel", pinned: status)
            steps.skipRest()
            steps.discard()
        }
    }

    /// The superset block, the finish sheet over a workout with a set logged, and the receipt once it is saved.
    @MainActor
    func test_supersetFinishSheetAndReceipt_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions, open: [Self.minimizeBroken])
        try audit.threeWays(launching: ["-LEDGER_UITEST_PROGRAM", "seed"]) { steps in
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
    static let screens: Set = ["solo card", "swap sheet", "rest panel", "superset block", "finish sheet", "receipt"]

    /// The workout cover's measured exclusions (F15-S2-3 to 9, the implementation notes).
    static var exclusions: [ScreenExclusion] {
        [
            .eyebrows([
                "UPPER A — PUSH FOCUS",
                "REMAINING",
                "5 LB",
                "2.5 LB",
                "1 REP",
                "TIME",
                "SETS",
                "LB MOVED",
                "LOGGED"
            ], on: screens),
            .shortLines([
                "UPPER A — PUSH FOCUS",
                "Barbell Bench Press",
                "5 × 5 @ 180 lb · RPE 8",
                "Superset · block 4 of 4",
                "Upper A — Push focus",
                "LB MOVED"
            ], on: screens),
            minimizeWhole,
            .underThePinnedPart(on: ["rest panel"]),
            .accentButtons(["Skip rest", "Save workout"], on: ["rest panel", "finish sheet"]),
            receiptDate
        ]
    }

    /// F15-S2-4 on the header's "Minimize", the ghost pill's button role: whole on one line at the default size,
    /// light and dark. At Accessibility XXXL it breaks inside the word: `minimizeBroken`.
    static var minimizeWhole: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on Minimize at the default size") {
            $0.summary == "Text clipped" && $0.identifier == "workout.header.minimize" && $0.way != .largest
                && screens.contains($0.screen)
        }
    }

    /// F15-S2-10, open: at Accessibility XXXL "Minimize" is drawn "Minimi / ze" (and "Finish" "Finis / h", which the
    /// audit does not report). A real layout finding, an expected failure until the follow-up PR after S2 lays the
    /// header's row out for the accessibility sizes.
    static var minimizeBroken: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-10", issue: "Minimize breaks inside the word at Accessibility XXXL") {
            $0.summary == "Text clipped" && $0.identifier == "workout.header.minimize" && $0.way == .largest
                && screens.contains($0.screen)
        }
    }

    /// F15-S2-9: the receipt's date, "Friday, November 13" (a caption, 12 pt tall), is no control. VoiceOver's
    /// escape, "Done", is set on the receipt's stack and so on each of its elements
    /// (`ReceiptTests.escape_isDone` performs it on the first), which the audit takes for a tap target.
    static var receiptDate: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-9", issue: "Hit area too small, the receipt's date") {
            $0.summary == "Hit area is too small" && $0.screen == "receipt" && $0.elementType == .staticText
                && $0.label.range(of: #"^[A-Z][a-z]+day, [A-Z][a-z]+ \d{1,2}$"#, options: .regularExpression) != nil
        }
    }
}
