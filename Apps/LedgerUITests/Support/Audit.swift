import XCTest

/// The three ways F15 audits a screen (S2, question 6, A): contrast differs by appearance, and clipping by size.
/// The hosted sweeps already cover every text size, so the running app is audited at the default size and at the
/// largest only. The appearance is the app's own Debug seam (`LaunchAppearance`, `Support/Appearance.swift`): on the
/// iOS 27.0 simulator the device's appearance does not reliably reach a launched app.
enum AuditWay: String, CaseIterable {
    case light
    case dark
    case largest = "light, Accessibility XXXL"

    var appearance: LaunchAppearance {
        self == .dark ? .dark : .light
    }

    /// The launch arguments that set the way's appearance and text size.
    var arguments: [String] {
        let size = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        return appearance.launchArguments + (self == .largest ? size : [])
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
    /// An issue whose presence on the same screen in the same way means this is not the finding.
    var unlessBeside: ((ScreenIssue) -> Bool)?
    let excuses: (ScreenIssue) -> Bool

    init(
        finding: String, issue: String, perScreenAndWay: Int? = nil, unlessBeside: ((ScreenIssue) -> Bool)? = nil,
        excuses: @escaping (ScreenIssue) -> Bool
    ) {
        self.finding = finding
        self.issue = issue
        self.perScreenAndWay = perScreenAndWay
        self.unlessBeside = unlessBeside
        self.excuses = excuses
    }

    /// Whether this names `issue`, one of `issues` (all a test's audits reported): its condition, and its count
    /// where it has one.
    func names(_ issue: ScreenIssue, among issues: [ScreenIssue]) -> Bool {
        guard excuses(issue) else {
            return false
        }
        let beside = issues.contains { unlessBeside?($0) == true && $0.screen == issue.screen && $0.way == issue.way }
        guard !beside else { return false }
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
    private(set) var way = AuditWay.light

    /// `open` names real findings not fixed yet, each by its finding ID: what one names is an expected failure
    /// (strict), so the test stays able to catch everything else, and fails the day the finding is fixed, so that
    /// the entry is taken out.
    init(for test: XCTestCase, exclusions: [ScreenExclusion], open: [ScreenExclusion] = []) {
        self.test = test
        self.exclusions = exclusions
        self.open = open
    }

    /// The exclusion that excuses `issue`, if one does.
    nonisolated static func exclusion(
        for issue: ScreenIssue, in exclusions: [ScreenExclusion], among issues: [ScreenIssue]? = nil
    ) -> ScreenExclusion? {
        exclusions.first { $0.names(issue, among: issues ?? [issue]) }
    }

    /// Launches the app three ways (`AuditWay`) with `arguments`, and runs `walk` each time: the walk reaches each
    /// screen and calls `audit(_:screen:)` on it. Then the verdict: every issue no exclusion excuses fails. The
    /// report of every issue is kept with the result at the test's end, also when a walk stopped midway.
    func threeWays(launching arguments: [String], walk: (Steps) throws -> Void) throws {
        try run(AuditWay.allCases, launching: arguments, walk: walk)
    }

    /// `threeWays`, in `ways` only.
    func run(_ ways: [AuditWay], launching arguments: [String], walk: (Steps) throws -> Void) throws {
        test.addTeardownBlock { self.attachReport() }
        for next in ways {
            way = next
            let steps = Steps(launching: arguments + next.arguments, for: test)
            // Today stands on the paper ground in light: the one screen every walk starts on where the appearance
            // can be read off the picture (never the cover or a sheet).
            XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10), "on Today")
            try test.assertDrawn(in: next.appearance, steps.app)
            try walk(steps)
            steps.app.terminate()
        }
        verdict()
    }

    /// One audit, of every type (or of `types`), of what is on screen, named `screen`. The screen and each reported
    /// element are pictured and kept. `pinned` is a part pinned over the page's end, if the screen has one.
    func audit(
        _ steps: Steps, screen: String, pinned: PinnedPart? = nil, types: XCUIAccessibilityAuditType = .all
    ) throws {
        let app = steps.app
        let name = "\(screen), \(way.rawValue)"
        Self.settle(app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app)
        steps.attachScreenshot(named: "\(name): screen")
        let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
        let window = app.windows.firstMatch.frame
        let pinnedPart = pinned.map { part in
            CGRect(x: window.minX, y: part.minY, width: window.width, height: window.maxY - part.minY)
        } ?? .null
        let pinnedNames: (identifiers: Set<String>, labels: Set<String>) = pinned?.names ?? ([], [])
        var pictured: [(String, XCUIElement)] = []
        try app.performAccessibilityAudit(for: types) { issue in
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
        // Drags near the leading edge, where no control or chart takes the touch, until `last` stands above the bar,
        // or the page stops: two drags in a row that leave its picture as it was (the picture, not an element, as a
        // lazy list drops the rows it scrolled past).
        // Where `last` ends: its text where it is one (a row's button reaches below its text by its padding), else
        // the element itself.
        let named = NSPredicate(format: "label BEGINSWITH %@", last)
        let (texts, any) = (page.staticTexts.matching(named), page.descendants(matching: .any).matching(named))
        let lastEnd = { (texts.firstMatch.exists ? texts : any).allElementsBoundByIndex.map(\.frame.maxY).max() }
        let top = barTop()
        let arrived = { lastEnd().map { $0 <= top } ?? false }
        var still = 0
        var picture = page.screenshot().pngRepresentation
        // From above the bar or pinned part (a drag that starts on a sheet's foot moves nothing) to near the top.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let frame = page.frame
        let start = min(frame.minY + frame.height * 0.8, barTop() - 24)
        for _ in 0 ..< 30 where still < 2 && !arrived() {
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
        XCTAssertLessThanOrEqual(lastEnd() ?? .infinity, top, "\(place): \(last) is under the bar")
    }

    /// Waits, at most ten pictures long, until two pictures in a row of `region` are the same: an audit taken while
    /// a selection or a sheet still moves measures colours half-way (a current legend row's accent letter over the
    /// fill it was leaving, measured once in S2a's review round). The region is the screen's first scroll view, the
    /// page: never the cover's header, whose elapsed time changes each second, nor the rest panel's ring.
    private static func settle(_ region: XCUIElement) {
        var picture = region.screenshot().pngRepresentation
        for _ in 0 ..< 10 {
            let next = region.screenshot().pngRepresentation
            if next == picture {
                return
            }
            picture = next
        }
    }

    /// The page's lowest text, button or field with a label: what a reader reads last.
    private static func lowest(on page: XCUIElement) -> XCUIElement? {
        let elements = page.staticTexts.allElementsBoundByIndex + page.buttons.allElementsBoundByIndex
            + page.textFields.allElementsBoundByIndex
        return elements.filter { $0.frame.height > 0 && !$0.label.isEmpty }.max { $0.frame.maxY < $1.frame.maxY }
    }

    /// Every issue, with its type and its verdict: excused, open, or not excused.
    private func attachReport() {
        let left = issues.filter { Self.exclusion(for: $0, in: exclusions, among: issues) == nil }
        let report = issues.map { issue in
            let excused = Self.exclusion(for: issue, in: exclusions, among: issues).map { "excused, \($0.finding)" }
            let opened = open.first { $0.names(issue, among: left) }.map { "open, \($0.finding)" }
            return "\(issue) type \(issue.type.rawValue)\n  \(issue.detail)\n  \(excused ?? opened ?? "NOT EXCUSED")"
        }
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "Audit issues"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// The issues no exclusion excuses fail the test; each open finding is a strict expected failure.
    private func verdict() {
        let left = issues.filter { Self.exclusion(for: $0, in: exclusions, among: self.issues) == nil }
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

extension ScreenAudit {
    /// Criterion 7 (S2b): in the Accessibility XXXL way, and in no other, the screen is pictured and each of its
    /// primary `actions` is scrolled to (in `page`, else the screen's first scroll view) and can be tapped.
    func reach(_ steps: Steps, screen: String, _ actions: [XCUIElement], in page: XCUIElement? = nil) {
        guard way == .largest else {
            return
        }
        steps.attachScreenshot(named: "\(screen), \(way.rawValue): primary actions")
        for action in actions {
            steps.scrollIntoReach(action, in: page)
        }
    }
}
