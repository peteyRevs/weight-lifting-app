#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Synchronization
    import Testing
    import UIKit

    /// Whether a read failed its test with the reader's advice about scroll views.
    private final nonisolated class Heard: Sendable {
        private let flag = Mutex(false)

        var isSet: Bool {
            flag.withLock { $0 }
        }

        func set() {
            flag.withLock { $0 = true }
        }
    }

    /// What stands beside the text inside the scroll view, or how the scroll view is wrapped.
    nonisolated enum ScrollCompany: String, CaseIterable, Sendable {
        case textOnly, toggle, textField, secureField, slider, stepper, segmentedPicker, datePicker
        case textEditor, horizontalRow, innerScrollView
        case identified, contained, labelled, list, form, navigationStack
    }

    /// What a read returned, and whether it failed the test over a scroll view.
    struct ScrollReading {
        let labels: [String]
        let wasLoud: Bool
    }

    extension RenderingSuites {
        /// F08 S2 close-out (G2 round 2): the hosted accessibility reader now fails a read that meets a scroll
        /// view, with a named opt-in for the parts around one (testing-strategy §2.5 and §2.6, "so a tree is
        /// never pinned from a reading that silently lacks what scrolls"). The question put to it here: can a
        /// test still pass on a reading that lacks what scrolls, without saying so?
        ///
        /// Each case puts a text and one more thing inside a scroll view, with a text above and a button below
        /// it, and reads the whole. A read is sound if it returns the text inside, or fails loudly.
        @Suite("Adversarial F08 S2 close-out · the loud accessibility reader", .tags(.design))
        struct ReaderCloseOutAdversarialTests {
            nonisolated static let advice = "cannot see inside a scroll view"

            /// A UIKit-backed control, as a settings page would hold beside its texts.
            @ViewBuilder
            static func control(_ kind: ScrollCompany) -> some View {
                switch kind {
                case .toggle: Toggle(isOn: .constant(true)) { Text(verbatim: "Plate math") }
                case .textField: TextField(text: .constant("Bench"), prompt: nil) { Text(verbatim: "Name") }
                case .secureField: SecureField(text: .constant("x"), prompt: nil) { Text(verbatim: "Secret") }
                case .slider: Slider(value: .constant(0.5)) { Text(verbatim: "Rest") }
                case .stepper: Stepper(value: .constant(3), in: 1 ... 12) { Text(verbatim: "Sets") }
                case .textEditor: TextEditor(text: .constant("Notes")).frame(height: 80)
                default: pickerOrScroller(kind)
                }
            }

            @ViewBuilder
            static func pickerOrScroller(_ kind: ScrollCompany) -> some View {
                switch kind {
                case .segmentedPicker:
                    Picker(selection: .constant(0)) {
                        Text(verbatim: "lb").tag(0)
                        Text(verbatim: "kg").tag(1)
                    } label: {
                        Text(verbatim: "Units")
                    }
                    .pickerStyle(.segmented)
                case .datePicker:
                    DatePicker(selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date) {
                        Text(verbatim: "Start")
                    }
                case .horizontalRow: ScrollView(.horizontal) { HStack { Text(verbatim: "Chip") } }
                case .innerScrollView: ScrollView { Text(verbatim: "Deeper") }.frame(height: 60)
                default: EmptyView()
                }
            }

            /// "Inside" and the case's companion in a scroll view, or in a container that scrolls, wrapped as
            /// the case says.
            @ViewBuilder
            static func scroller(_ kind: ScrollCompany) -> some View {
                let page = VStack {
                    Text(verbatim: "Inside")
                    control(kind)
                }
                switch kind {
                case .identified: ScrollView { page }.accessibilityIdentifier("screen.scroll")
                case .contained: ScrollView { page }.accessibilityElement(children: .contain)
                case .labelled:
                    ScrollView { page }.accessibilityElement(children: .contain)
                        .accessibilityLabel(Text(verbatim: "Program"))
                case .list: List { page }
                case .form: Form { page }
                case .navigationStack: NavigationStack { ScrollView { page } }
                default: ScrollView { page }
                }
            }

            /// "Above", the case's scroller, and the button "Below".
            static func screen(_ kind: ScrollCompany) -> some View {
                VStack {
                    Text(verbatim: "Above")
                    scroller(kind)
                    Button(action: {}, label: { Text(verbatim: "Below") })
                }
                .frame(height: 700)
            }

            static func read(_ view: some View, outsideScrollViews: Bool = false) -> ScrollReading {
                let heard = Heard()
                var labels: [String] = []
                withKnownIssue(isIntermittent: true) {
                    labels = view.accessibilityElements(outsideScrollViews: outsideScrollViews).map(\.label)
                } matching: { issue in
                    guard issue.description.contains(Self.advice) else {
                        return false
                    }
                    heard.set()
                    return true
                }
                return ScrollReading(labels: labels, wasLoud: heard.isSet)
            }

            @Test(
                "A read that lacks what scrolls says so, whatever else the scroll view holds",
                arguments: ScrollCompany.allCases
            )
            func scrollView_withAnyCompany_isReadOrFailsLoudly(_ kind: ScrollCompany) {
                let reading = Self.read(Self.screen(kind))
                #expect(
                    reading.wasLoud || reading.labels.contains("Inside"),
                    "silent and without what scrolls: \(reading.labels)"
                )
            }

            @Test(
                "Asked for what stands outside scroll views, the reader gives that alone and fails nothing",
                arguments: [
                    ScrollCompany.textOnly, .toggle, .textField, .slider, .stepper, .horizontalRow, .innerScrollView
                ]
            )
            func outsideScrollViews_leavesOutAllThatScrolls(_ kind: ScrollCompany) {
                let reading = Self.read(Self.screen(kind), outsideScrollViews: true)
                #expect(reading.labels == ["Above", "Below"], "\(kind)")
                #expect(!reading.wasLoud)
            }

            @Test("The same parts without a scroll view are read whole and fail nothing: the page convention")
            func page_withoutAScrollView_isReadWhole() {
                let parts = VStack {
                    Text(verbatim: "Above")
                    Text(verbatim: "Inside")
                    Button(action: {}, label: { Text(verbatim: "Below") })
                }
                let reading = Self.read(parts)
                #expect(reading.labels == ["Above", "Inside", "Below"])
                #expect(!reading.wasLoud)
            }
        }
    }

    /// A limit of the reader, and the audit of F06's helper.
    extension RenderingSuites.ReaderCloseOutAdversarialTests {
        /// A limit of the reader, kept as a test so that it stays known (as the copy audit's limits are): a
        /// multi-line text field is a `UITextView`, which is a scroll view, and yields no element in a test
        /// process. So a page that holds one cannot be read by the default reader, whose advice (host the
        /// page without its scroll view) does not fit, and the opt-in reads the rest and leaves the field
        /// out. If the reader learns to read a text editor, this test fails and the limit goes.
        @Test("Limit: a text editor on a page makes the read loud, and the opt-in reads all but the editor")
        func limit_textEditorOnAPage_isLoud() {
            let editor = VStack {
                Text(verbatim: "Notes")
                TextEditor(text: .constant("Felt strong")).frame(height: 120)
                Button(action: {}, label: { Text(verbatim: "Save") })
            }
            let field = VStack {
                Text(verbatim: "Notes")
                TextField(text: .constant("Felt strong"), axis: .vertical) { Text(verbatim: "Note") }
                Button(action: {}, label: { Text(verbatim: "Save") })
            }
            for reading in [Self.read(editor), Self.read(field)] {
                #expect(reading.wasLoud)
                #expect(reading.labels == ["Notes", "Save"])
            }
            for reading in [
                Self.read(editor, outsideScrollViews: true),
                Self.read(field, outsideScrollViews: true)
            ] {
                #expect(!reading.wasLoud)
                #expect(reading.labels == ["Notes", "Save"])
            }
        }

        @Test("F06's helper titleOffset still fails loudly on a scrolling sheet unless its caller opts in")
        func titleOffset_onAScrollingSheet_isLoudByDefault() throws {
            let appearance = SnapshotAppearance(.dark, .large)
            let sheet = SheetChrome("Swap exercise", cancel: "Cancel") {} content: {
                ScrollView { Text(verbatim: "Alternative") }
            }
            let heard = Heard()
            var loud: CGFloat?
            withKnownIssue(isIntermittent: true) {
                // If the helper throws here, `loud` stays nil and the comparison below fails the test.
                loud = try? RenderingSuites.Slice3CloseoutSheetAdversarialTests.titleOffset(
                    sheet, title: "Swap exercise", height: 437, appearance
                )
            } matching: { issue in
                guard issue.description.contains(Self.advice) else {
                    return false
                }
                heard.set()
                return true
            }
            #expect(heard.isSet, "the helper's default is the loud reader")
            let quiet = try RenderingSuites.Slice3CloseoutSheetAdversarialTests.titleOffset(
                sheet, title: "Swap exercise", height: 437, appearance, outsideScrollViews: true
            )
            #expect(loud == quiet, "the opt-in changes what fails, not what is measured")
        }
    }
#endif
