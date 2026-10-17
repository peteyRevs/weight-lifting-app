#if os(iOS) && DEBUG
    @testable import FeatureProgram
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9: the program's name and the library's search field, read through UIKit. In a package test
    /// process a text field is no accessibility element, so the hosted reader does not see the two and the
    /// pinned trees do not hold them; here each is found as the `UITextField` it is, with its placeholder and
    /// its text. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    ///
    /// **Not covered by any hosted test:** typing. A hosted field takes no text from a test (text set on it is
    /// put back, and no key reaches it), so that a typed name is sent as `.rename` and a typed query as
    /// `.setQuery` waits for the UI tests of S13 and S14.
    @Suite("Program text fields", .serialized, .tags(.feature))
    struct ProgramTextFieldTests {
        /// A hosted view, with the means to draw another in its place: the same `@State` and focus live on.
        final class Hosted {
            let host: UIHostingController<AnyView>
            private let window: UIWindow

            init(_ view: some View) {
                host = UIHostingController(rootView: AnyView(view))
                window = SceneLessWindow.make(
                    frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874)
                )
                window.rootViewController = host
                window.isHidden = false
                host.view.layoutIfNeeded()
            }

            func show(_ view: some View) {
                host.rootView = AnyView(view)
                settle()
            }

            /// Lays the view out and lets the main run loop turn once, without waiting: a change of focus
            /// reaches SwiftUI on the next turn.
            func settle() {
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date())
                host.view.layoutIfNeeded()
            }

            var fields: [UITextField] {
                Self.fields(in: host.view)
            }

            func close() {
                window.isHidden = true
                window.rootViewController = nil
            }

            private static func fields(in view: UIView) -> [UITextField] {
                ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
            }
        }

        /// The placeholder and the text of each text field of a state's parts.
        static func fields(of preview: ProgramPreview) -> [[String]] {
            let hosted = Hosted(ProgramParts(preview: preview))
            defer { hosted.close() }
            return hosted.fields.map { [$0.placeholder ?? "", $0.text ?? ""] }
        }

        @Test("The builder's one field holds the program's name over the placeholder Program name")
        func builder_nameField_holdsTheName() {
            #expect(Self.fields(of: .builder) == [["Program name", "Upper / Lower"]])
            #expect(Self.fields(of: .sixteenWeeks) == [["Program name", ProgramPreviewData.longName]])
        }

        @Test("The library's one field holds the query over the placeholder Search exercises")
        func library_searchField_holdsTheQuery() {
            #expect(Self.fields(of: .library) == [["Search exercises", ""]])
            #expect(Self.fields(of: .libraryNothing) == [["Search exercises", "zzz"]])
        }

        private static func header(_ name: String, sent: @escaping (ProgramBuilderAction) -> Void) -> some View {
            ProgramHeader(
                model: ProgramBuilderModel.Header(eyebrow: "MY PROGRAM", name: name, namePlaceholder: "Program name"),
                send: sent
            )
        }

        @Test("The name field follows the stored name while it has no focus, and sends nothing for it")
        func nameField_withoutFocus_followsTheStoredName() throws {
            var sent: [ProgramBuilderAction] = []
            let hosted = Hosted(Self.header("Upper / Lower") { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            #expect(field.text == "Upper / Lower")
            hosted.show(Self.header("Push Pull Legs") { sent.append($0) })
            #expect(field.text == "Push Pull Legs")
            #expect(sent.isEmpty, "a name that came from the store is not sent back to it")
        }

        @Test("While the name field has focus it keeps its draft; when it loses focus it takes the stored name")
        func nameField_withFocus_keepsItsDraft() throws {
            var sent: [ProgramBuilderAction] = []
            let hosted = Hosted(Self.header("Upper / Lower") { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            try #require(field.becomeFirstResponder(), "the hosted field takes no focus")
            hosted.settle()
            hosted.show(Self.header("Upper / Lower, cleaned") { sent.append($0) })
            #expect(field.text == "Upper / Lower", "the stored name is not written into a field being edited")
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(field.text == "Upper / Lower, cleaned")
        }

        /// A limit of the hosted reader, kept as a test so that it stays known: it passes a one-line text field
        /// in silence. When it learns to read one this fails, and the two fields go into `ProgramTrees`.
        @Test("Limit: the hosted accessibility reader does not read a text field")
        func fields_areNotReadByTheHostedReader() throws {
            let model = try ProgramPreview.builder.builderModel()
            #expect(ProgramHeader(model: model.header) { _ in }.stops() == [.heading("MY PROGRAM")])
            let search = try ProgramPreview.library.libraryModel().search
            #expect(ExerciseSearchField(model: search) { _ in }.stops().isEmpty)
        }
    }
#endif
