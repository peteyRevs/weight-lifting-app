import XCTest

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
