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
    /// Whether the element is one of the pinned part's own (by identifier, else by label), not the page's.
    var inPinnedPart = false

    var description: String {
        // An issue the system reports with no element has a null frame, which has no whole numbers.
        let box = frame.isNull ? "no frame"
            : "x \(Int(frame.minX)) y \(Int(frame.minY)) w \(Int(frame.width)) h \(Int(frame.height))"
        return "\(screen), \(way.rawValue): \(summary) [\(elementType.rawValue) \"\(label)\" \(identifier) \(box)]"
    }
}

/// A part pinned over the page's end, which the page scrolls under: its top element, how far above that element the
/// part begins (measured in the pictures), and its own elements, so an issue on one of them is never taken for the
/// page's line under it.
@MainActor
struct PinnedPart {
    let top: XCUIElement
    let margin: CGFloat
    let members: [XCUIElement]

    /// The rest panel: its 16 pt padding and rule put its top 17 pt above `workout.rest.status`.
    static func restPanel(in app: XCUIApplication) -> PinnedPart {
        let status = app.descendants(matching: .any).matching(identifier: "workout.rest.status").firstMatch
        return PinnedPart(
            top: status,
            margin: 17,
            members: [status, app.buttons["workout.rest.extend"], app.buttons["workout.rest.skip"]]
        )
    }

    /// A sheet's foot: its rule stands 11 pt above its one button.
    static func sheetFoot(_ button: XCUIElement) -> PinnedPart {
        PinnedPart(top: button, margin: 11, members: [button])
    }

    /// Where the part begins on screen.
    var minY: CGFloat {
        top.frame.minY - margin
    }

    /// The identifiers and labels of the part's own elements and of what they hold.
    var names: (identifiers: Set<String>, labels: Set<String>) {
        let all = members.flatMap { [$0] + $0.descendants(matching: .any).allElementsBoundByIndex }.filter(\.exists)
        return (Set(all.map(\.identifier).filter { !$0.isEmpty }), Set(all.map(\.label)))
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
    /// screen and calls `audit(_:screen:)` on it. Then the verdict: every issue no exclusion excuses fails. The
    /// report of every issue is kept with the result at the test's end, also when a walk stopped midway.
    func threeWays(launching arguments: [String], walk: (Steps) throws -> Void) throws {
        test.addTeardownBlock { self.attachReport() }
        for next in AuditWay.allCases {
            way = next
            let steps = Steps(launching: arguments + next.arguments, for: test)
            try walk(steps)
            steps.app.terminate()
        }
        verdict()
    }

    /// One audit, every type, of what is on screen, named `screen`. The screen and each reported element are
    /// pictured and kept. `pinned` is a part pinned over the page's end, if the screen has one.
    func audit(_ steps: Steps, screen: String, pinned: PinnedPart? = nil) throws {
        let app = steps.app
        let name = "\(screen), \(way.rawValue)"
        Self.settle(app)
        steps.attachScreenshot(named: "\(name): screen")
        let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
        let window = app.windows.firstMatch.frame
        let pinnedPart = pinned.map { part in
            CGRect(x: window.minX, y: part.minY, width: window.width, height: window.maxY - part.minY)
        } ?? .null
        let pinnedNames: (identifiers: Set<String>, labels: Set<String>) = pinned?.names ?? ([], [])
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
                found.inPinnedPart = found.identifier.isEmpty ? pinnedNames.labels.contains(found.label)
                    : pinnedNames.identifiers.contains(found.identifier)
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

    /// The proof that makes "under the tab bar" or "under a pinned part" a false positive (testing-strategy §2.7, as
    /// `TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar`): the page holding a text or
    /// button labelled `anchor` (never a page behind the screen), swiped until it stops moving, ends with the text
    /// or button whose label is or starts with `last` (no labelled text or button of it lies lower), and that stands
    /// whole above `barTop`, so whatever rested under the bar or the part can be read.
    func expectScrollsClear(
        _ steps: Steps, screen: String, anchor: String, last: String, above barTop: () -> CGFloat
    ) {
        let app = steps.app
        let page = app.scrollViews.containing(NSPredicate(format: "label == %@", anchor)).firstMatch
        XCTAssertTrue(page.exists, "\(screen): no page holds \(anchor)")
        // Drags near the leading edge, where no control or chart takes the touch, until the page stops: two drags
        // in a row that leave its picture as it was (a lazy list drops what it scrolled past, so no element of it
        // can be the mark).
        var still = 0
        var picture = page.screenshot().pngRepresentation
        // From above the bar or pinned part (a drag that starts on a sheet's foot moves nothing) to near the top.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let frame = page.frame
        let start = min(frame.minY + frame.height * 0.8, barTop() - 24)
        for _ in 0 ..< 30 where still < 2 {
            let from = origin.withOffset(CGVector(dx: frame.minX + 24, dy: start))
            from.press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.minX + 24, dy: frame.minY + 40))
            )
            let next = page.screenshot().pngRepresentation
            still = next == picture ? still + 1 : 0
            picture = next
        }
        let lowest = Self.lowest(on: page)
        steps.attachScreenshot(named: "\(screen), \(way.rawValue): scrolled to the end")
        let place = "\(screen), \(way.rawValue)"
        XCTAssertTrue(
            lowest?.label.hasPrefix(last) == true,
            "\(place): the page ends with \(lowest?.label ?? "nothing")"
        )
        XCTAssertLessThanOrEqual(lowest?.frame.maxY ?? .infinity, barTop(), "\(place): \(last) is under the bar")
    }

    /// Waits, at most ten pictures long, until two pictures of the screen in a row are the same: an audit taken while
    /// a selection or a sheet still moves measures colours half-way (a current legend row's accent letter over the
    /// fill it was leaving, measured once in S2a's review round). A screen with a clock that runs (the rest panel) is
    /// never still; it is audited after the ten.
    private static func settle(_ app: XCUIApplication) {
        var picture = app.screenshot().pngRepresentation
        for _ in 0 ..< 10 {
            let next = app.screenshot().pngRepresentation
            if next == picture {
                return
            }
            picture = next
        }
    }

    /// The page's lowest text or button with a label: what a reader reads last.
    private static func lowest(on page: XCUIElement) -> XCUIElement? {
        let elements = page.staticTexts.allElementsBoundByIndex + page.buttons.allElementsBoundByIndex
        return elements.filter { $0.frame.height > 0 && !$0.label.isEmpty }.max { $0.frame.maxY < $1.frame.maxY }
    }

    /// Every issue, with its type and its verdict: excused, open, or not excused.
    private func attachReport() {
        let report = issues.map { issue in
            let excused = Self.exclusion(for: issue, in: exclusions).map { "excused, \($0.finding)" }
            let opened = open.first { $0.names(issue, among: issues) }.map { "open, \($0.finding)" }
            return "\(issue) type \(issue.type.rawValue)\n  \(issue.detail)\n  \(excused ?? opened ?? "NOT EXCUSED")"
        }
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "Audit issues"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// The issues no exclusion excuses fail the test; each open finding is a strict expected failure.
    private func verdict() {
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
