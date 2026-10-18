import XCTest

/// One issue as the system's audit reported it on a step of onboarding, with what is needed to judge it.
struct AuditFinding: CustomStringConvertible {
    var appearance = "light"
    var step = 1
    var type: XCUIAccessibilityAuditType
    /// The system's short name for the issue: "Contrast failed", "Contrast nearly passed", "Text clipped".
    var summary: String
    var detail = ""
    var identifier = ""
    var isStaticText = false
    var label = ""
    var frame = CGRect.null
    /// Where the page's scroll view ended on screen when the step was audited.
    var pageBottom = CGFloat.infinity
    /// Where the step's option buttons stood on screen.
    var options: [CGRect] = []

    var description: String {
        "\(appearance), step \(step): \(summary) [\(isStaticText ? "text" : "element") \"\(label)\" \(identifier)]"
    }
}

/// An issue the audit reports on this screen that is known not to be a fault of it (testing-strategy §2.7): the
/// kind of issue, the element or elements it is excused on, and why. Nothing wider is excused: the same kind on
/// another element, or another kind on the same element, fails the test.
struct AuditExclusion {
    let issue: String
    let reason: String
    let excuses: (AuditFinding) -> Bool
}

extension OnboardingAdversarial {
    /// F8-S3-2, as measured in the S3 touch-up and ruled by the orchestrator (2026-10-05).
    static var auditExclusions: [AuditExclusion] {
        [
            AuditExclusion(
                issue: "\"Contrast nearly passed\" on the primary button, onboarding.cta",
                reason: """
                White on the accent is 3.1:1, which the design system accepts for the button role's large bold \
                text (F06; the comment on the role in LedgerFont).
                """,
                excuses: {
                    $0.type == .contrast && $0.summary == "Contrast nearly passed" && $0.identifier == "onboarding.cta"
                }
            ),
            AuditExclusion(
                issue: "\"Text clipped\" on the step's title, onboarding.title",
                reason: """
                The audit predicts clipping for a text whose line height is below its font's own and whose width \
                at the largest size would pass the screen's edge. The title wraps and grows, and nothing is cut at \
                any size (the display role's 1.06 is LedgerDesign's; whether it changes is a design question).
                """,
                excuses: { $0.type == .textClipped && $0.identifier == "onboarding.title" }
            ),
            AuditExclusion(
                issue: "\"Contrast failed\" on a text of an option, onboarding.option.<n>, that reaches below the page",
                reason: """
                The pinned buttons hide that line in part or whole, and the audit measures the screen inside the \
                line's frame: the pinned button and the ground, not the line, whose ink is 4.83:1 on the ground in \
                light and 5.04:1 in dark. Which hidden line it reports is not stable, so the condition is the line's \
                place, not its words.
                """,
                excuses: { finding in
                    finding.type == .contrast && finding.summary == "Contrast failed" && finding.isStaticText
                        && finding.frame.maxY > finding.pageBottom
                        && finding.options.contains { $0.insetBy(dx: -1, dy: -1).contains(finding.frame) }
                }
            )
        ]
    }

    /// The exclusion that excuses `finding`, if one does.
    static func exclusion(for finding: AuditFinding) -> AuditExclusion? {
        auditExclusions.first { $0.excuses(finding) }
    }

    /// Runs the system's audit on each step, in light and in dark. An issue no exclusion excuses fails the
    /// test. Everything the system reported is attached, excused or not, with what it says about each.
    @MainActor
    func auditEachStep(arguments: [String], size: String) throws {
        let before = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = before }
        var findings: [AuditFinding] = []
        for (appearance, name) in [(XCUIDevice.Appearance.light, "light"), (.dark, "dark")] {
            XCUIDevice.shared.appearance = appearance
            let app = launch(arguments)
            XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 15))
            for (index, heading) in Self.headings.enumerated() {
                if index > 0 {
                    continueTo(heading, in: app)
                }
                findings += try audit(app, step: index + 1, appearance: name)
            }
            app.terminate()
        }
        let report = findings.map { finding in
            let verdict = Self.exclusion(for: finding).map { "excused (\($0.issue))" } ?? "NOT EXCUSED"
            return "\(finding.description)\n  \(finding.detail)\n  \(verdict)"
        }
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "Audit issues at \(size)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let left = findings.filter { Self.exclusion(for: $0) == nil }.map(\.description)
        XCTAssertEqual(left, [], "at \(size): \(findings.count) reported, \(findings.count - left.count) excused")
    }

    /// One audit of the step on screen: every issue, with where the page ends and where the options stand.
    @MainActor
    private func audit(_ app: XCUIApplication, step: Int, appearance: String) throws -> [AuditFinding] {
        let pageBottom = app.scrollViews.firstMatch.frame.maxY
        let options = (0 ... 3).map { app.buttons["onboarding.option.\($0)"] }.filter(\.exists).map(\.frame)
        var findings: [AuditFinding] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            findings.append(AuditFinding(
                appearance: appearance,
                step: step,
                type: issue.auditType,
                summary: issue.compactDescription,
                detail: issue.detailedDescription,
                identifier: element?.identifier ?? "",
                isStaticText: element?.elementType == .staticText,
                label: element?.label ?? "",
                frame: element?.frame ?? .null,
                pageBottom: pageBottom,
                options: options
            ))
            return true
        }
        return findings
    }

    /// The exclusions excuse what they name and nothing wider. No app is launched: the findings are made here.
    func test_auditExclusions_excuseNothingWider() {
        let excused = [
            AuditFinding(type: .contrast, summary: "Contrast nearly passed", identifier: "onboarding.cta"),
            AuditFinding(
                type: .textClipped,
                summary: "Text clipped",
                identifier: "onboarding.title",
                isStaticText: true
            ),
            Self.optionLine(at: 660), // its lower half is behind the pinned part
            Self.optionLine(at: 680) // nearly all of it is
        ]
        XCTAssertEqual(excused.map { Self.exclusion(for: $0) != nil }, [true, true, true, true])
        let stillFailing = Self.findingsOutsideTheExclusions.filter { Self.exclusion(for: $0) != nil }
        XCTAssertEqual(stillFailing.map(\.description), [], "excused, and should not be")
    }

    /// "Contrast failed" on a text 80 pt high at `minY`, on a step whose page ends at 700 pt and whose one
    /// option stands from 600 to 760 pt unless `options` says otherwise.
    static func optionLine(
        at minY: CGFloat,
        in options: [CGRect] = [CGRect(x: 20, y: 600, width: 360, height: 160)]
    ) -> AuditFinding {
        AuditFinding(
            type: .contrast,
            summary: "Contrast failed",
            isStaticText: true,
            frame: CGRect(x: 20, y: minY, width: 300, height: 80),
            pageBottom: 700,
            options: options
        )
    }

    /// Near misses of each exclusion: the same kind of issue on another element, another kind on the same
    /// element, and a hidden line that is not an option's.
    static var findingsOutsideTheExclusions: [AuditFinding] {
        var option = optionLine(at: 660)
        option.isStaticText = false
        return [
            AuditFinding(type: .contrast, summary: "Contrast nearly passed", identifier: "onboarding.skip"),
            AuditFinding(type: .contrast, summary: "Contrast failed", identifier: "onboarding.cta"),
            AuditFinding(type: .contrast, summary: "Contrast nearly passed", identifier: "onboarding.title"),
            AuditFinding(type: .textClipped, summary: "Text clipped", identifier: "onboarding.option.0"),
            AuditFinding(type: .textClipped, summary: "Text clipped", identifier: "onboarding.cta"),
            AuditFinding(type: .hitRegion, summary: "Hit area is too small", identifier: "onboarding.cta"),
            AuditFinding(type: .dynamicType, summary: "Dynamic Type unsupported", identifier: "onboarding.title"),
            optionLine(at: 610), // an option's line in full view
            optionLine(at: 660, in: []), // a text behind the pinned part that is no option's
            optionLine(at: 660, in: [CGRect(x: 20, y: 200, width: 360, height: 160)]), // nor in the option shown
            option // the option itself, not a text of it
        ]
    }
}
