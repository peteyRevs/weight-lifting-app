import XCTest

/// The three ways F15 audits a screen (S2, question 6, A): contrast differs by appearance, and clipping by size.
/// The hosted sweeps already cover every text size, so the running app is audited at the default size and at the
/// largest only. The appearance is the app's own Debug seam, `-LEDGER_UITEST_APPEARANCE`: on the iOS 27.0
/// simulator neither `XCUIDevice.appearance` nor `simctl ui appearance` reaches a launched app.
enum AuditWay: String, CaseIterable {
    case light
    case dark
    case largest = "light, Accessibility XXXL"

    /// The launch arguments that set the way's appearance and text size.
    var arguments: [String] {
        switch self {
        case .light: ["-LEDGER_UITEST_APPEARANCE", "light"]
        case .dark: ["-LEDGER_UITEST_APPEARANCE", "dark"]
        case .largest: [
                "-LEDGER_UITEST_APPEARANCE",
                "light",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
    }
}

/// One issue the system's audit reported on a screen, with what is needed to judge it: the system's words for it,
/// and the element's type, identifier, label and frame. Where the tab bar stood is kept too, because what rests
/// under the floating bar is measured through its glass (testing-strategy §2.7).
struct ScreenIssue: CustomStringConvertible {
    var way = AuditWay.light
    var screen = ""
    var type: XCUIAccessibilityAuditType
    /// The system's short name for the issue: "Contrast failed", "Contrast nearly passed", "Text clipped".
    var summary: String
    var detail = ""
    var elementType = XCUIElement.ElementType.any
    var identifier = ""
    var label = ""
    var frame = CGRect.null
    var tabBar = CGRect.null
    /// The part of the screen pinned over the page's end (the rest panel, a sheet's bottom button and its rule),
    /// from its top to the screen's bottom; null where nothing is pinned.
    var pinned = CGRect.null

    var description: String {
        // An issue the system reports with no element has a null frame, which has no whole numbers.
        let box = frame.isNull ? "no frame"
            : "x \(Int(frame.minX)) y \(Int(frame.minY)) w \(Int(frame.width)) h \(Int(frame.height))"
        return "\(screen), \(way.rawValue): \(summary) [\(elementType.rawValue) \"\(label)\" \(identifier) \(box)]"
    }
}

/// An issue the audit reports on a screen that was measured and judged no fault of it: its finding ID
/// (`F15-S2-<n>`, in the implementation notes, with the measurement), the issue and element in words, and the
/// condition. Nothing wider is excused: the same kind on another element, or another kind on the same element,
/// fails (`AuditExclusionsTests`).
struct ScreenExclusion {
    let finding: String
    let issue: String
    /// For an issue the system reports with no element: how many the measurement found on one screen in one way.
    /// Another count, more or fewer, is not this finding.
    var perScreenAndWay: Int?
    let excuses: (ScreenIssue) -> Bool

    init(finding: String, issue: String, perScreenAndWay: Int? = nil, excuses: @escaping (ScreenIssue) -> Bool) {
        self.finding = finding
        self.issue = issue
        self.perScreenAndWay = perScreenAndWay
        self.excuses = excuses
    }

    /// Whether this names `issue`, one of `issues` (all a test's audits reported): its condition, and its count
    /// where it has one.
    func names(_ issue: ScreenIssue, among issues: [ScreenIssue]) -> Bool {
        guard excuses(issue) else {
            return false
        }
        guard let perScreenAndWay else {
            return true
        }
        let alike = issues.filter { excuses($0) && $0.screen == issue.screen && $0.way == issue.way }
        return alike.count == perScreenAndWay
    }
}

/// F15's audit runner (S2, criterion 6): each screen a walk reaches is audited with every audit type; every issue,
/// excused or not, is kept with the result with the element's picture; and an issue no exclusion excuses fails the
/// test. One place for the reporting, so a change of the system's audit is met once (risk R10).
@MainActor
final class ScreenAudit {
    private let test: XCTestCase
    private let exclusions: [ScreenExclusion]
    private let open: [ScreenExclusion]
    private(set) var issues: [ScreenIssue] = []
    private var way = AuditWay.light

    /// `open` names real findings not fixed yet, each by its finding ID: what one names is an expected failure
    /// (strict), so the test stays able to catch everything else, and fails the day the finding is fixed, so that
    /// the entry is taken out.
    init(for test: XCTestCase, exclusions: [ScreenExclusion], open: [ScreenExclusion] = []) {
        self.test = test
        self.exclusions = exclusions
        self.open = open
    }

    /// The exclusion that excuses `issue`, if one does.
    nonisolated static func exclusion(for issue: ScreenIssue, in exclusions: [ScreenExclusion]) -> ScreenExclusion? {
        exclusions.first { $0.excuses(issue) }
    }

    /// Launches the app three ways (`AuditWay`) with `arguments`, and runs `walk` each time: the walk reaches each
    /// screen and calls `audit(_:screen:)` on it. Then the verdict: every issue no exclusion excuses fails.
    func threeWays(launching arguments: [String], walk: (Steps) throws -> Void) throws {
        for next in AuditWay.allCases {
            way = next
            let steps = Steps(launching: arguments + next.arguments, for: test)
            try walk(steps)
            steps.app.terminate()
        }
        verdict()
    }

    /// One audit, every type, of what is on screen, named `screen`. The screen and each reported element are
    /// pictured and kept. `pinned` is the top element of a part pinned over the page's end: the part is taken to
    /// begin `ScreenExclusion.pinnedMargin` above it (its padding and rule).
    func audit(_ steps: Steps, screen: String, pinned: XCUIElement? = nil) throws {
        let app = steps.app
        let name = "\(screen), \(way.rawValue)"
        steps.attachScreenshot(named: "\(name): screen")
        let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
        let window = app.windows.firstMatch.frame
        let pinnedPart = pinned.map { element in
            let top = element.frame.minY - ScreenExclusion.pinnedMargin
            return CGRect(x: window.minX, y: top, width: window.width, height: window.maxY - top)
        } ?? .null
        var pictured: [(String, XCUIElement)] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            var found = ScreenIssue(
                way: self.way,
                screen: screen,
                type: issue.auditType,
                summary: issue.compactDescription,
                detail: issue.detailedDescription,
                tabBar: tabBar,
                pinned: pinnedPart
            )
            if let element = issue.element {
                found.elementType = element.elementType
                found.identifier = element.identifier
                found.label = element.label
                found.frame = element.frame
                pictured.append(("\(name): \(issue.compactDescription): \(element.label)", element))
            }
            self.issues.append(found)
            return true
        }
        for (title, element) in pictured where element.exists && !element.frame.isEmpty {
            let attachment = XCTAttachment(screenshot: element.screenshot())
            attachment.name = title
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
    }

    /// The proof that makes "under the tab bar" a false positive (testing-strategy §2.7, as
    /// `TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar`): the page, swiped to its end,
    /// stands whole above the floating bar, so whatever rested under the bar can be read.
    func expectScrollsClearOfTheTabBar(_ steps: Steps, screen: String) {
        let app = steps.app
        let page = app.scrollViews.firstMatch
        for _ in 0 ..< 8 {
            page.swipeUp(velocity: .fast)
        }
        let texts = page.staticTexts.allElementsBoundByIndex.filter { $0.frame.height > 0 }
        let last = texts.max { $0.frame.maxY < $1.frame.maxY }
        let bar = app.tabBars.firstMatch.frame
        steps.attachScreenshot(named: "\(screen), \(way.rawValue): scrolled to the end")
        XCTAssertNotNil(last, "\(screen): no text on the page")
        if let last {
            let place = "\(screen), \(way.rawValue): \(last.label)"
            XCTAssertLessThanOrEqual(last.frame.maxY, bar.minY, "\(place) is under the bar")
        }
    }

    /// Every issue with its verdict kept with the result; those no exclusion excuses fail the test.
    private func verdict() {
        let report = issues.map { issue in
            let verdict = Self.exclusion(for: issue, in: exclusions).map { "excused, \($0.finding)" } ?? "NOT EXCUSED"
            return "\(issue)\n  \(issue.detail)\n  \(verdict)"
        }
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "Audit issues"
        attachment.lifetime = .keepAlways
        test.add(attachment)
        let left = issues.filter { Self.exclusion(for: $0, in: exclusions) == nil }
        let isOpen = { (issue: ScreenIssue) in self.open.contains { $0.names(issue, among: left) } }
        let unknown = left.filter { !isOpen($0) }.map(\.description)
        XCTAssertEqual(unknown, [], "\(issues.count) reported, \(issues.count - left.count) excused")
        for finding in open {
            let named = left.filter { finding.names($0, among: left) }.map(\.description)
            XCTExpectFailure("\(finding.finding), open: \(finding.issue)", strict: true) {
                XCTAssertEqual(named, [], "\(finding.finding) is still open")
            }
        }
    }
}
