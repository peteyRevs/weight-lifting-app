#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F08 S2, criterion 10 as revised after round 1 (and standards §7's 44 pt): nothing truncates or is cut off
    /// at any Dynamic Type size, the largest included, on the narrowest phone the app supports; the page always
    /// scrolls inside the screen, under the pinned buttons, which stay in reach.
    ///
    /// Close-out (round 2): the screen has one layout, its pinned part under `ScrollView { OnboardingPage }`,
    /// and no reader in a test process sees inside a scroll view. So each case is measured twice, as
    /// testing-strategy §2.6 splits it:
    /// - **the page followed by the pinned part** (`AdversarialParts`), at the phone's width and unlimited
    ///   height: every element, its frame, its size with nothing pressing on it;
    /// - **the real screen in a window of the phone's size and safe area:** the pinned elements (all this
    ///   file's own walk gets there, knowingly) and the one scroll view's own numbers.
    ///
    /// No text of the screen has a line limit (the page's, the footer's, `PrimaryButton`'s and `PillButton`'s
    /// sources hold none), so a text can only lose lines by being given less height than it needs: the pinned
    /// part by the screen, which is compared with its unpressed height, and the page by the scroll view, whose
    /// content must be as tall as the page unpressed. Set `TEST_RUNNER_LEDGER_ADVERSARIAL_RENDER_DIR` for
    /// `xcodebuild` and each case is also written there as a PNG, for a reader's eyes.
    @Suite("Adversarial F08 S2 · the layout on the narrowest and the widest phone, at every text size")
    struct OnboardingLayoutAdversarialTests {
        /// One state on one phone in one appearance.
        nonisolated struct Case: Sendable, CustomStringConvertible {
            let name: String
            let state: OnboardingState
            let phone: PhoneFrame
            let appearance: SnapshotAppearance

            var description: String {
                "\(name), \(phone), \(appearance)"
            }

            static let states: [(String, OnboardingState)] = [
                ("goal", OnboardingState()),
                ("days", OnboardingState(step: .days)),
                ("program-4", OnboardingState(step: .program)),
                ("program-5", OnboardingState(step: .program, days: .five)),
                ("program-6-kg", OnboardingState(step: .program, days: .six, units: .kg)),
                ("failed-6-kg", OnboardingState(step: .program, days: .six, units: .kg, phase: .failed)),
                ("failed-goal", OnboardingState(phase: .failed))
            ]

            /// Every Dynamic Type size, light and dark by turns, and the matrix's six appearances.
            static let everySize: [SnapshotAppearance] = DynamicTypeSize.allCases.enumerated().map { index, size in
                SnapshotAppearance(index.isMultiple(of: 2) ? .light : .dark, size)
            } + SnapshotAppearance.phoneMatrix

            /// Criterion 10's cases. With `LEDGER_TEST_LANE=nightly` or `LEDGER_ADVERSARIAL_FULL=1`: every state
            /// on the narrowest, the mini, the references' and the widest phone at every text size (504 cases).
            /// Otherwise a representative part: the narrowest and the widest phone, the longest states, the
            /// smallest, the default and the two largest text sizes (testing-strategy §6).
            static let all: [Case] = AdversarialLane.runsEverything
                ? cases(states, [.smallest, .mini, .seventeen, .widest], everySize)
                : cases(
                    states.filter { ["goal", "program-6-kg", "failed-6-kg"].contains($0.0) },
                    [.smallest, .widest],
                    // The hosted PR run keeps `TestSweep`'s sizes, the largest among them (port, criterion 25).
                    TestSweep.subset([
                        SnapshotAppearance(.light, .xSmall), SnapshotAppearance(.light, .large),
                        SnapshotAppearance(.dark, .accessibility3), SnapshotAppearance(.dark, .accessibility5)
                    ]) { TestSweep.representativeSizes.contains($0.dynamicTypeSize) }
                )

            /// F8-S2-1's cases, in every lane: each state on the narrowest phone, the mini and the widest at
            /// the largest text size there is.
            static let largest: [Case] = cases(
                states, [.smallest, .mini, .widest], [SnapshotAppearance(.dark, .accessibility5)]
            )

            static func cases(
                _ states: [(String, OnboardingState)],
                _ phones: [PhoneFrame],
                _ appearances: [SnapshotAppearance]
            ) -> [Case] {
                states.flatMap { name, state in
                    phones.flatMap { phone in
                        appearances.map { Case(name: name, state: state, phone: phone, appearance: $0) }
                    }
                }
            }
        }

        /// The page's scroll view on the phone.
        struct Scroll {
            let frame: CGRect
            let content: CGSize
            let insets: UIEdgeInsets
            let offset: CGPoint

            /// The height the page can be seen in.
            var room: CGFloat {
                frame.height - insets.top - insets.bottom
            }
        }

        /// What a case measures.
        struct Measured {
            /// Every element of the page and the pinned part, with unlimited height.
            let free: [Spoken]
            /// The screen's elements outside its scroll view, in the phone's window: the pinned part.
            let phone: [Spoken]
            let scrolls: [Scroll]

            static let pinnedLabels = [
                BriefCopy.saveFailed, BriefCopy.continueTitle, BriefCopy.startTraining, BriefCopy.retry,
                BriefCopy.skipSetup
            ]

            /// The pinned part: the failure line, the primary button and "Skip setup".
            static func pinned(_ elements: [Spoken]) -> [Spoken] {
                elements.filter { pinnedLabels.contains($0.label) }
            }

            static func page(_ elements: [Spoken]) -> [Spoken] {
                elements.filter { !pinnedLabels.contains($0.label) }
            }

            /// From the top of the page's first element to the bottom of its last, with nothing pressing on it.
            var freePageHeight: CGFloat {
                let page = Self.page(free)
                return (page.last?.frame.maxY ?? 0) - (page.first?.frame.minY ?? 0)
            }
        }

        static func screen(_ state: OnboardingState) -> OnboardingScreen {
            OnboardingScreen(model: OnboardingPresentation.make(state, locale: Fixtures.locale), send: { _ in })
        }

        /// Each case is laid out once for the suite's tests.
        static var known: [String: Measured] = [:]

        static func measure(_ shown: Case) -> Measured {
            if let measured = known[shown.description] {
                return measured
            }
            let measured = lay(shown)
            known[shown.description] = measured
            return measured
        }

        static func lay(_ shown: Case) -> Measured {
            AccessibilityTree.whileBuilt {
                let tall = PhoneHost(AdversarialParts(shown.state), on: shown.phone.tall, shown.appearance)
                let free = tall.spoken()
                tall.close()
                let host = PhoneHost(screen(shown.state), on: shown.phone, shown.appearance)
                defer { host.close() }
                // This walk returns nothing of what is inside the scroll view, and is used for that.
                let phone = host.spoken()
                render(host, shown, "top")
                let scrolls = host.scrollViews.map { scroll in
                    Scroll(
                        frame: host.frame(of: scroll), content: scroll.contentSize,
                        insets: scroll.adjustedContentInset, offset: scroll.contentOffset
                    )
                }
                for scroll in host.scrollViews {
                    let lowest = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                    guard lowest > scroll.contentOffset.y + 1 else {
                        continue
                    }
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: lowest), animated: false)
                    host.layout()
                    render(host, shown, "end")
                }
                return Measured(free: free, phone: phone, scrolls: scrolls)
            }
        }

        /// Writes the case as drawn, when the run names a folder for it.
        static func render(_ host: PhoneHost, _ shown: Case, _ part: String) {
            guard let folder = ProcessInfo.processInfo.environment["LEDGER_ADVERSARIAL_RENDER_DIR"], !folder.isEmpty,
                  let png = host.png()
            else {
                return
            }
            let phone = shown.phone.name.replacingOccurrences(of: " ", with: "-")
            let file = "\(shown.name)_\(phone)_\(shown.appearance)_\(part).png"
            // A render that cannot be written is only a missing picture: the measurements do not need it.
            try? png.write(to: URL(filePath: folder).appending(path: file))
        }

        static func overlaps(_ elements: [Spoken]) -> [String] {
            elements.indices.flatMap { first in
                elements.indices.filter { $0 > first }.compactMap { second -> String? in
                    let shared = elements[first].frame.intersection(elements[second].frame)
                    guard !shared.isNull, shared.width > 1, shared.height > 1 else {
                        return nil
                    }
                    return "\(elements[first]) over \(elements[second])"
                }
            }
        }
    }

    /// The measurements.
    extension OnboardingLayoutAdversarialTests {
        @Test(
            "At each phone's width every element is read, between the edges, apart, and each control 44 pt",
            arguments: Case.all
        )
        func elements_atThePhonesWidth_areWholeAndApart(_ shown: Case) {
            let free = Self.measure(shown).free
            let expected = OnboardingVoiceOverAdversarialTests.reading(shown.state).joined(separator: ", ")
            #expect(free.map(\.text).joined(separator: ", ") == expected)
            let outside = free.filter { $0.frame.minX < -0.5 || $0.frame.maxX > shown.phone.width + 0.5 }
            #expect(outside.isEmpty, "\(outside)")
            let empty = free.filter { $0.frame.width < 1 || $0.frame.height < 1 }
            #expect(empty.isEmpty, "\(empty)")
            #expect(Self.overlaps(free).isEmpty)
            let small = free.filter { $0.isButton && ($0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001) }
            #expect(small.isEmpty, "\(small)")
        }

        @Test(
            "On the phone the primary button and Skip setup are whole, in reach and as large as unpressed",
            arguments: Case.all
        )
        func pinnedControls_onThePhone_areInReachAndWhole(_ shown: Case) {
            let measured = Self.measure(shown)
            let visible = CGRect(
                x: 0, y: shown.phone.safeTop, width: shown.phone.width,
                height: shown.phone.height - shown.phone.safeTop - shown.phone.safeBottom
            )
            let pinned = Measured.pinned(measured.phone)
            let unpressed = Measured.pinned(measured.free)
            #expect(pinned.map(\.text) == unpressed.map(\.text))
            #expect(pinned.count { $0.isButton } == 2, "\(pinned)")
            let cut = pinned.filter { !visible.insetBy(dx: -0.5, dy: -0.5).contains($0.frame) }
            #expect(cut.isEmpty, "outside \(visible): \(cut)")
            #expect(Self.overlaps(pinned).isEmpty)
            for (shownElement, free) in zip(pinned, unpressed) {
                // F8-S2-1: a sentence that is given less height than it needs gives up a line to an ellipsis.
                let lost = free.frame.height - shownElement.frame.height
                #expect(lost < 0.5, "\(shownElement.text) lost \(lost) pt of \(free.frame.height)")
                #expect(abs(free.frame.width - shownElement.frame.width) < 0.5, "\(shownElement) against \(free)")
            }
        }

        @Test(
            "On the phone the page is whole inside one scroll view that starts at its top and ends at the pinned part",
            arguments: Case.all
        )
        func page_onThePhone_scrollsWhole(_ shown: Case) throws {
            let measured = Self.measure(shown)
            let floor = try #require(Measured.pinned(measured.phone).map(\.frame.minY).min())
            #expect(Measured.page(measured.phone).isEmpty, "control: the page is inside the scroll view")
            #expect(measured.scrolls.count == 1, "the screen is its pinned part and one scroll view")
            let scroll = try #require(measured.scrolls.first)
            #expect(scroll.frame.maxY - scroll.insets.bottom <= floor + 0.5, "the page scrolls under the pinned part")
            #expect(scroll.frame.minY + scroll.insets.top <= shown.phone.safeTop + 0.5, "\(scroll)")
            #expect(abs(scroll.frame.width - shown.phone.width) < 0.5, "\(scroll)")
            #expect(scroll.content.width <= shown.phone.width + 0.5, "the page scrolls sideways")
            #expect(scroll.content.height >= measured.freePageHeight - 0.5, "\(scroll) for \(measured.freePageHeight)")
            #expect(abs(scroll.offset.y + scroll.insets.top) < 0.5, "the page opens \(scroll.offset.y) pt from its top")
            #expect(scroll.room >= 44, "the page has \(scroll.room) pt to be seen in")
        }

        @Test(
            "At the largest text size there is, on the narrowest and the widest phone, nothing is cut (F8-S2-1)",
            arguments: Case.largest
        )
        func everything_atTheLargestTextSize_isWhole(_ shown: Case) throws {
            elements_atThePhonesWidth_areWholeAndApart(shown)
            pinnedControls_onThePhone_areInReachAndWhole(shown)
            try page_onThePhone_scrollsWhole(shown)
        }

        @Test("Control: the measurement tells a sentence that lost a line from a whole one")
        func harness_seesASqueezedSentence() {
            let large = SnapshotAppearance(.dark, .accessibility5)
            let sentence = Text(verbatim: BriefCopy.saveFailed).frame(maxWidth: .infinity, alignment: .leading)
            let heights = AccessibilityTree.whileBuilt {
                let free = PhoneHost(sentence, on: PhoneFrame.smallest.tall, large)
                defer { free.close() }
                let whole = free.spoken().first?.frame.height ?? 0
                let pressed = PhoneHost(sentence.frame(height: whole - 20), on: PhoneFrame.smallest.tall, large)
                defer { pressed.close() }
                return (whole, pressed.spoken().first?.frame.height ?? 0)
            }
            #expect(heights.0 > 60, "control: the sentence takes more than one line here")
            #expect(
                heights.0 - heights.1 > 15,
                "a sentence given 20 pt too little reads \(heights.1) of \(heights.0) pt"
            )
        }
    }
#endif
