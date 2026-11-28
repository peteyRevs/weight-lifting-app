import XCTest

/// F18 S7, the test plan's audit line: the system's accessibility audit (`performAccessibilityAudit()`, every type) on
/// each of the watch's screens, reached as `WatchFlows` reaches them: before a workout (with no program, and with
/// today's day), the set, the rest, the session list, the end overlay with no set and with sets logged, and the
/// summary, at the default text size and at the largest (`AX5`, where the pages scroll). Every issue is kept with the
/// result and fails the test: none is excused. What the first run reported was fixed on the screens (the exercise's
/// name is a taller target; the set dots and the heart rate read as text). Nightly only, as the iPhone's audits.
final class WatchAudit: XCTestCase {
    /// The watch's largest text size.
    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private var issues: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        issues = []
    }

    @MainActor
    func test_noProgram_passesTheAudit() throws {
        let steps = WatchSteps(for: self)
        try audit(steps, screen: "before a workout, no program")
        verdict()
    }

    @MainActor
    func test_everyWorkoutScreen_passesTheAudit() throws {
        try walk(launching: WatchSteps.seededMonday)
    }

    @MainActor
    func test_everyWorkoutScreen_atTheLargestSize_passesTheAudit() throws {
        try walk(launching: WatchSteps.seededMonday + Self.largest)
    }

    @MainActor
    private func walk(launching arguments: [String]) throws {
        let steps = WatchSteps(launching: arguments, for: self)
        XCTAssertTrue(steps.reads(steps.todayTitle, WatchSteps.upperA))
        try audit(steps, screen: "before a workout, today's day")
        steps.start()
        try audit(steps, screen: "set ready")
        steps.openEnd()
        try audit(steps, screen: "end, no set logged")
        steps.tap("workout.end.keepLifting")
        XCTAssertTrue(steps.app.buttons["workout.list.end"].waitForExistence(timeout: 5), "Keep lifting: the list")
        try audit(steps, screen: "session list")
        steps.tap("workout.list.close")

        steps.tap("workout.ready.doneSet")
        XCTAssertTrue(steps.reads(steps.restTitle, "REST"), "a logged set starts a rest")
        try audit(steps, screen: "rest")
        steps.tap("workout.rest.skip")
        XCTAssertTrue(steps.reads(steps.setLabel, "SET 2 OF 5"))
        steps.openEnd()
        try audit(steps, screen: "end, a set logged")
        steps.tap("workout.end.save")
        XCTAssertTrue(steps.app.staticTexts["workout.summary.title"].waitForExistence(timeout: 10))
        try audit(steps, screen: "summary")
        steps.tap("workout.summary.done")
        verdict()
    }

    /// One audit of what is on screen, with a picture of it; each issue is kept, excused or not.
    @MainActor
    private func audit(_ steps: WatchSteps, screen: String) throws {
        steps.attachScreenshot(named: screen)
        try steps.app.performAccessibilityAudit { issue in
            let element = issue.element.map { element in
                let frame = element.frame.integral
                return "\(element.elementType.rawValue) \"\(element.label)\" \(element.identifier) "
                    + "w \(Int(frame.width)) h \(Int(frame.height))"
            }
            self.issues.append(
                "\(screen): \(issue.compactDescription) [\(element ?? "no element")] \(issue.detailedDescription)"
            )
            return true
        }
    }

    /// Any issue fails the test; the report of all of them is kept with the result.
    @MainActor
    private func verdict() {
        let attachment = XCTAttachment(string: issues.joined(separator: "\n"))
        attachment.name = "Audit issues"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(issues, [], "\(issues.count) reported")
    }
}
