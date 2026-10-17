#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// A page and what it holds, as a screen that scrolls is built: a title and a row.
    private struct ReaderPage: View {
        var body: some View {
            VStack {
                Text(verbatim: "Title").accessibilityAddTraits(.isHeader)
                Button(action: {}, label: { Text(verbatim: "Row") })
            }
        }
    }

    extension RenderingSuites {
        /// The hosted accessibility reader and scroll views (F08 S2 fix round 1; testing-strategy §2.6, "A
        /// screen that scrolls"). In a package test process a hosted SwiftUI `ScrollView` hands UIKit no
        /// accessibility children, so the reader used to return what stood around it and nothing of what
        /// scrolls, in silence. It now fails the test that hands it one, and says what to do; a caller that
        /// knowingly reads the parts around a scroll view asks for them with `outsideScrollViews: true`.
        @Suite("AccessibilityReader", .tags(.design))
        struct AccessibilityReaderTests {
            private nonisolated static let advice = "cannot see inside a scroll view"

            @Test("A scroll view fails the read with what to do, whichever reader is handed it")
            func scrollView_failsTheRead() {
                let screen = VStack {
                    ScrollView { ReaderPage() }
                    Button(action: {}, label: { Text(verbatim: "Pinned") })
                }
                withKnownIssue {
                    let read = screen.accessibilityElements().map(\.label)
                    // What it still returns is the part outside the scroll view: the short tree that a table
                    // would otherwise have been written from.
                    #expect(read == ["Pinned"])
                } matching: { $0.description.contains(Self.advice) && $0.description.contains("Host the page") }
                withKnownIssue {
                    screen.withAccessibilityElements { _ in }
                } matching: { $0.description.contains(Self.advice) }
                withKnownIssue {
                    screen.withLiveAccessibilityElements { read in _ = read() }
                } matching: { $0.description.contains(Self.advice) }
            }

            @Test("A scroll view alone, with nothing around it, fails the read too")
            func scrollViewAlone_failsTheRead() {
                withKnownIssue {
                    #expect(ScrollView { ReaderPage() }.accessibilityElements().isEmpty)
                } matching: { $0.description.contains(Self.advice) }
            }

            @Test("The page without the scroll view, followed by the pinned part, is read whole and in order")
            func pageAndPinnedPart_areRead() {
                let parts = VStack {
                    ReaderPage()
                    Button(action: {}, label: { Text(verbatim: "Pinned") })
                }
                #expect(parts.accessibilityElements().map(\.label) == ["Title", "Row", "Pinned"])
            }

            @Test("Asked for what stands outside scroll views, each reader returns that and fails nothing")
            func outsideScrollViews_readsThePinnedPartsWithoutFailing() {
                let sheet = VStack {
                    Text(verbatim: "Title").accessibilityAddTraits(.isHeader)
                    ScrollView { ReaderPage() }
                    Button(action: {}, label: { Text(verbatim: "Pinned") })
                }
                #expect(sheet.accessibilityElements(outsideScrollViews: true).map(\.label) == ["Title", "Pinned"])
                let live = sheet.withAccessibilityElements(outsideScrollViews: true) { elements in
                    elements.map { $0.accessibilityLabel ?? "" }
                }
                #expect(live == ["Title", "Pinned"])
                let twice = sheet.withLiveAccessibilityElements(outsideScrollViews: true) { read in
                    [read().count, read().count]
                }
                #expect(twice == [2, 2])
            }

            @Test("Asked for what stands outside scroll views, a view that holds none is read as it always was")
            func outsideScrollViews_withoutAScrollView_changesNothing() {
                let parts = VStack {
                    ReaderPage()
                    Button(action: {}, label: { Text(verbatim: "Pinned") })
                }
                let plain = parts.accessibilityElements()
                #expect(parts.accessibilityElements(outsideScrollViews: true) == plain)
                #expect(plain.map(\.label) == ["Title", "Row", "Pinned"])
            }

            @Test("A scroll view alone, read for what stands outside it, is an empty tree and no failure")
            func outsideScrollViews_scrollViewAlone_isEmpty() {
                #expect(ScrollView { ReaderPage() }.accessibilityElements(outsideScrollViews: true).isEmpty)
            }

            @Test("A view with nothing to read and no scroll view is an empty tree, not a failure")
            func emptyTree_withoutAScrollView_isNoFailure() {
                #expect(HairlineRule().accessibilityElements().isEmpty)
            }
        }
    }
#endif
