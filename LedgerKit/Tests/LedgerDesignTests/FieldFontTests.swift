#if os(iOS)
    @testable import LedgerDesign
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// `ledgerFieldFont(_:)`: a one-line field in a type role, on a line that holds the font's tails
        /// while UIKit edits it, with its `.top` guide where a text of the role has its top. Measured on a
        /// hosted `UITextField` with the focus, since only the editor clips; `SceneLessWindow` is internal
        /// to `LedgerSnapshotTesting`, hence the `@testable` import.
        @Suite("FieldFont", .tags(.design))
        struct FieldFontTests {
            /// "Gyp" as a text of the role with a field laid over it, top on top; one of the two is drawn, in
            /// white on black. The field is set by `style`, applied to it directly: the `.top` guide is the
            /// field's own, and a branch or a stack around it would have a top of its own.
            static func pair(
                _ role: LedgerFont.Role,
                drawsField: Bool,
                style: (TextField<Text>) -> some View = { $0.ledgerFieldFont(.title) }
            ) -> some View {
                Text("Gyp")
                    .ledgerFont(role)
                    .foregroundStyle(drawsField ? Color.clear : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        style(TextField("", text: .constant("Gyp")))
                            .foregroundStyle(drawsField ? Color.white : Color.clear)
                    }
                    .padding(LedgerSpacing.xxl)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.black)
            }

            /// The box, in points, of the white ink of `view`, hosted at `size`, its text field being edited
            /// or not. The caret is blue and is not counted.
            static func ink(
                _ view: some View,
                at size: DynamicTypeSize,
                _ weight: LegibilityWeight = .regular,
                isEdited: Bool
            ) throws -> CGRect {
                let set = view.environment(\.dynamicTypeSize, size).environment(\.legibilityWeight, weight)
                let host = UIHostingController(rootView: set)
                let window = SceneLessWindow.make(frame: CGRect(
                    x: 0,
                    y: 0,
                    width: SnapshotConfig.phoneWidth,
                    height: 300
                ))
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                host.view.layoutIfNeeded()
                if isEdited {
                    try #require(Self.field(in: host.view)?.becomeFirstResponder() == true, "the field takes no focus")
                    RunLoop.main.run(until: Date())
                    host.view.layoutIfNeeded()
                }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image {
                    host.view.layer.render(in: $0.cgContext)
                }
                let drawn = try #require(image.cgImage.flatMap(PixelBuffer.init))
                let inked = drawn.pixels.indices.filter { drawn.pixels[$0].red > 150 && drawn.pixels[$0].green > 150 }
                let (rows, columns) = (inked.map { $0 / drawn.width }, inked.map { $0 % drawn.width })
                let (top, bottom) = try (#require(rows.min(), "no ink"), #require(rows.max()))
                let (left, right) = try (#require(columns.min()), #require(columns.max()))
                return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
                    .applying(CGAffineTransform(scaleX: 1 / 3, y: 1 / 3))
            }

            static func field(in view: UIView) -> UITextField? {
                (view as? UITextField) ?? view.subviews.lazy.compactMap(field(in:)).first
            }

            @Test(
                "A field in the title role draws its tails whole while it is edited, where a text of the role does",
                arguments: [DynamicTypeSize.xSmall, .large, .accessibility3, .accessibility5],
                [LegibilityWeight.regular, .bold]
            )
            func titleField_edited_drawsItsTailsWhole(_ size: DynamicTypeSize, _ weight: LegibilityWeight) throws {
                let text = try Self.ink(Self.pair(.title, drawsField: false), at: size, weight, isEdited: false)
                let field = try Self.ink(Self.pair(.title, drawsField: true), at: size, weight, isEdited: true)
                // A pixel of the drawing at 3× is a third of a point.
                #expect(field.height > text.height - 0.34, "the tails are cut: text \(text), field \(field)")
                #expect(
                    abs(field.minY - text.minY) < 2 && abs(field.minX - text.minX) < 1,
                    "text \(text), field \(field)"
                )
            }

            /// The fault the variant is for, so that the test above cannot pass by measuring nothing: the
            /// same field under `ledgerFont(.title)`, whose line is 1, loses its tails while it is edited.
            @Test("Control: a field under ledgerFont(.title) is cut while it is edited")
            func titleField_underTheRolesLine_isCut() throws {
                let text = try Self.ink(Self.pair(.title, drawsField: false), at: .large, isEdited: false)
                let cut = Self.pair(.title, drawsField: true) { $0.ledgerFont(.title) }
                let field = try Self.ink(cut, at: .large, isEdited: true)
                #expect(field.height < text.height - 2, "text \(text), field \(field)")
            }
        }
    }
#endif
