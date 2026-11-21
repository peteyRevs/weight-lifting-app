#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// The exercise sheet's name field over an empty and a blank name, measured as Program's
    /// `DayEditorViewsNameAdversarialTests.emptyName_showsThePlaceholderOnce` measures `NameField`: hosted in a window,
    /// drawn dark, with the focus and without it, and drawn again with the `UITextField` hidden, so that what is still
    /// there is the drawn text's and what went was the field's. Only the field's own frame is read, inside the box's
    /// outline and under the heading.
    ///
    /// **Not covered by any hosted test:** typing the spaces, which a hosted field does not take
    /// (`ProgramTextFieldTests`).
    @Suite("Exercise sheet name placeholder", .serialized, .tags(.feature))
    struct CreateExerciseNamePlaceholderTests {
        /// A hosted name field on the dark ground, at the iPhone 17's width inside the sheet's margins.
        final class Shown {
            private let host: UIHostingController<AnyView>
            private let window: UIWindow
            let field: UITextField
            /// The drawing's scale, at which a box is measured: a pixel is a third of a point.
            let scale: CGFloat = 3

            init(_ text: String) throws {
                let view = VStack(spacing: 0) {
                    CreateExerciseNameField(model: .init(label: "Name", text: text, problem: nil)) { _ in }
                        .frame(width: 353)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .background(LedgerColor.ground)
                .environment(\.colorScheme, .dark)
                host = UIHostingController(rootView: AnyView(view))
                host.overrideUserInterfaceStyle = .dark
                window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 400))
                window.rootViewController = host
                window.isHidden = false
                host.view.layoutIfNeeded()
                field = try #require(Self.fields(in: host.view).first)
                settle()
            }

            /// Lays the view out and lets the main run loop turn once: a change of focus reaches SwiftUI on the next.
            func settle() {
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date())
                host.view.layoutIfNeeded()
            }

            func focus(_ isFocused: Bool) throws {
                try #require(isFocused ? field.becomeFirstResponder() : field.resignFirstResponder())
                settle()
                settle()
            }

            /// The box, in points of the window, around the pixels of the field's frame that `isIncluded` picks;
            /// `.null` when there is none.
            func box(hidingTheField: Bool = false, _ isIncluded: (Pixel) -> Bool) throws -> CGRect {
                field.isHidden = hidingTheField
                defer { field.isHidden = false }
                let view: UIView = host.view
                view.layoutIfNeeded()
                let frame = field.convert(field.bounds, to: view)
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let image = UIGraphicsImageRenderer(bounds: frame, format: format).image {
                    view.layer.render(in: $0.cgContext)
                }
                let drawn = try #require(image.cgImage.flatMap(PixelBuffer.init))
                var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
                for down in 0 ..< drawn.height {
                    for across in 0 ..< drawn.width where isIncluded(drawn.pixel(column: across, row: down)) {
                        (minX, maxX) = (min(minX, across), max(maxX, across))
                        (minY, maxY) = (min(minY, down), max(maxY, down))
                    }
                }
                guard maxX >= 0 else {
                    return .null
                }
                return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                    .applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
                    .offsetBy(dx: frame.minX, dy: frame.minY)
            }

            /// Anything off the dark ground but the caret, which is blue: letters, a placeholder.
            func anything(hidingTheField: Bool = false) throws -> CGRect {
                try box(hidingTheField: hidingTheField) { $0.red > 40 && Int($0.blue) - Int($0.red) < 60 }
            }

            /// The name's letters, near white; the placeholder's faint ink is far darker.
            func letters(hidingTheField: Bool = false) throws -> CGRect {
                try box(hidingTheField: hidingTheField) { $0.red > 150 && $0.green > 150 }
            }

            func close() {
                window.isHidden = true
                window.rootViewController = nil
            }

            private static func fields(in view: UIView) -> [UITextField] {
                ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
            }
        }

        @Test(
            "An empty name shows the placeholder once, from the field; a blank one, from the text under it",
            arguments: ["", "   "]
        )
        func emptyName_showsThePlaceholderOnce(_ text: String) throws {
            let shown = try Shown(text)
            defer { shown.close() }
            for isFocused in [false, true] {
                if isFocused {
                    try shown.focus(true)
                }
                // A name of spaces is no empty name to UIKit, so the field keeps its own placeholder back. The name
                // field draws it under the field, with the focus and without it: the store keeps the spaces.
                let drawsItsOwn = !text.isEmpty
                #expect(
                    try shown.anything(hidingTheField: true).isNull == !drawsItsOwn,
                    "focus \(isFocused): the text under the field draws the placeholder: \(drawsItsOwn)"
                )
                #expect(try !shown.anything().isNull, "focus \(isFocused): nothing is drawn")
                // The placeholder is drawn in faint ink, never as the name's letters.
                #expect(try shown.letters().isNull, "focus \(isFocused): letters are drawn")
            }
            #expect(shown.field.placeholder == "Name")
            #expect(shown.field.text == text, "the field holds the name as typed")
        }

        /// So that a blank name reads as an empty one: the drawn placeholder is as big as the field's own and stands
        /// where it does, as the drawn name stands where the field draws it. The field's line stands a little off the
        /// text's, which Program allows the name 2 pt of (`NameFieldLineTests.focus_keepsTheTails`); measured here,
        /// at the default size, the drawn placeholder is 1.3 pt lower than the field's own without the focus and
        /// 1.7 pt with it, and 0.7 pt to its leading side with the focus.
        @Test("The placeholder over a blank name stands where the field's own stands over an empty one")
        func blankNamesPlaceholder_standsWhereTheFieldsOwnDoes() throws {
            /// What `text` draws without the focus, then with it, each in a window of its own.
            func drawn(_ text: String) throws -> [CGRect] {
                let shown = try Shown(text)
                defer { shown.close() }
                let without = try shown.anything()
                try shown.focus(true)
                return try [without, shown.anything()]
            }
            let (empty, blank) = try (drawn(""), drawn("   "))
            for (index, (own, overBlank)) in zip(empty, blank).enumerated() {
                let text = "focus \(index == 1): the field's own at \(own), the drawn one at \(overBlank)"
                #expect(abs(own.width - overBlank.width) < 1 && abs(own.height - overBlank.height) < 0.7, "\(text)")
                #expect(abs(own.minX - overBlank.minX) < 1 && abs(own.minY - overBlank.minY) < 2, "\(text)")
            }
        }
    }
#endif
