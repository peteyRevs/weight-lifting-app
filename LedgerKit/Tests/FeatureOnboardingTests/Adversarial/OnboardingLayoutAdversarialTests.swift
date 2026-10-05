#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F08 S2 adversarial round 1, criterion 10 (and standards §7's 44 pt): the screen in a window of a phone's size,
    /// with that phone's safe area, at every appearance of the snapshot matrix. The narrowest phones iOS 26 runs on
    /// are 375 pt wide (iPhone SE, 12 mini, 13 mini); the SE is also the shortest, 667 pt.
    ///
    /// Measured from the elements UIKit hands VoiceOver: each one's frame is where its text or its button is. A
    /// scene-less test window gets no elements for what is inside a SwiftUI `ScrollView` (checked on iOS 27.0: a
    /// key window and turns of the run loop change nothing), so where the page scrolls, its elements are measured
    /// in a window of the same width and unlimited height, and the phone's window gives the pinned buttons and
    /// the scroll view's own numbers. Set `TEST_RUNNER_LEDGER_ADVERSARIAL_RENDER_DIR` for `xcodebuild` and each
    /// case is also written there as a PNG, for a reader's eyes: truncation inside a frame cannot be measured.
    @Suite("Adversarial F08 S2 · the layout on the narrowest phones, at every text size")
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

            /// Criterion 10's cases: every state on every phone in the matrix's six appearances. The PR lane lays
            /// out a representative part (the smallest phone and the references' phone, the longest states, the
            /// default and the largest text), the nightly lane all 126 (testing-strategy §6).
            static let all: [Case] = AdversarialLane.isNightly
                ? cases(states, [.smallest, .mini, .seventeen], SnapshotAppearance.phoneMatrix)
                : cases(
                    states.filter { ["goal", "program-6-kg", "failed-6-kg"].contains($0.0) },
                    [.smallest, .seventeen],
                    [SnapshotAppearance(.light, .large), SnapshotAppearance(.dark, .accessibility3)]
                )

            /// Beyond criterion 10's bound: the text sizes above the matrix's largest. The brief's body asks for
            /// "Dynamic Type to AX5 … (no truncation)", and standards §7 for the accessibility sizes.
            static let beyond: [Case] = AdversarialLane.isNightly
                ? cases(
                    states,
                    [.smallest, .mini, .seventeen],
                    [SnapshotAppearance(.dark, .accessibility4), SnapshotAppearance(.dark, .accessibility5)]
                )
                : cases(
                    states.filter { ["program-6-kg", "failed-6-kg"].contains($0.0) },
                    [.smallest, .seventeen],
                    [SnapshotAppearance(.dark, .accessibility5)]
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

        /// The page's scroll view on the phone, when the page does not fit.
        struct Scroll {
            let frame: CGRect
            let content: CGSize
            let insets: UIEdgeInsets
        }

        /// What a case measures.
        struct Measured {
            /// Every element with unlimited height: nothing presses on anything.
            let free: [Spoken]
            /// The elements the phone's window gives: all of them when the page fits, the pinned ones when it scrolls.
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
                let tall = PhoneHost(screen(shown.state), on: shown.phone.tall, shown.appearance)
                let free = tall.spoken()
                tall.close()
                let host = PhoneHost(screen(shown.state), on: shown.phone, shown.appearance)
                defer { host.close() }
                let phone = host.spoken()
                render(host, shown, "top")
                let scrolls = host.scrollViews.map { scroll in
                    Scroll(
                        frame: host.frame(of: scroll),
                        content: scroll.contentSize,
                        insets: scroll.adjustedContentInset
                    )
                }
                for scroll in host.scrollViews {
                    let lowest = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
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
            let small = free.filter { $0.isButton && ($0.frame.width < 44 || $0.frame.height < 44) }
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
                let lost = free.frame.height - shownElement.frame.height
                #expect(lost < 0.5, "\(shownElement.text) lost \(lost) pt of \(free.frame.height)")
                #expect(abs(free.frame.width - shownElement.frame.width) < 0.5, "\(shownElement) against \(free)")
            }
        }

        @Test(
            "On the phone the page is whole: it fits above the pinned part, or all of it scrolls there",
            arguments: Case.all
        )
        func page_onThePhone_fitsOrScrollsWhole(_ shown: Case) throws {
            let measured = Self.measure(shown)
            let floor = try #require(Measured.pinned(measured.phone).map(\.frame.minY).min())
            let page = Measured.page(measured.phone)
            guard page.isEmpty else {
                // It fits: every element as large as unpressed, the first under the safe area's top, the last
                // above the pinned part.
                let unpressed = Measured.page(measured.free)
                #expect(page.map(\.text) == unpressed.map(\.text))
                let squeezed = zip(page, unpressed).filter { $0.frame.height < $1.frame.height - 0.5 }.map(\.0)
                #expect(squeezed.isEmpty, "\(squeezed)")
                #expect((page.first?.frame.minY ?? 0) >= shown.phone.safeTop - 0.5)
                #expect((page.last?.frame.maxY ?? 0) <= floor + 0.5, "the page runs under the pinned part")
                return
            }
            // It scrolls: one scroll view, which ends where the pinned part begins, as wide as the phone, holding
            // at least the page's unpressed height.
            let scroll = try #require(measured.scrolls.first, "no element of the page, and no scroll view either")
            #expect(measured.scrolls.count == 1)
            #expect(scroll.frame.maxY - scroll.insets.bottom <= floor + 0.5, "the page scrolls under the pinned part")
            #expect(scroll.content.width <= shown.phone.width + 0.5, "the page scrolls sideways")
            #expect(scroll.content.height >= measured.freePageHeight - 0.5, "\(scroll) for \(measured.freePageHeight)")
            let room = scroll.frame.height - scroll.insets.top - scroll.insets.bottom
            #expect(
                scroll.content.height > room,
                "the page fits (\(scroll.content.height) in \(room)) and still scrolls"
            )
        }

        @Test(
            "Beyond the matrix, at the text sizes above its largest, every element and the pinned part are whole",
            arguments: Case.beyond
        )
        func everything_beyondTheMatrix_isStillWhole(_ shown: Case) throws {
            elements_atThePhonesWidth_areWholeAndApart(shown)
            pinnedControls_onThePhone_areInReachAndWhole(shown)
            try page_onThePhone_fitsOrScrollsWhole(shown)
        }

        @Test("Control: the smallest phone at the largest text scrolls, and the iPhone 17 at the default does not")
        func harness_measuresBothWaysOfShowingThePage() {
            let large = SnapshotAppearance(.light, .accessibility3)
            let six = OnboardingState(step: .program, days: .six, units: .kg)
            let pressed = Self.measure(Case(name: "program-6-kg", state: six, phone: .smallest, appearance: large))
            #expect(Measured.page(pressed.phone).isEmpty)
            #expect(pressed.scrolls.count == 1)
            let roomy = Case(
                name: "goal", state: OnboardingState(), phone: .seventeen, appearance: SnapshotAppearance(
                    .light,
                    .large
                )
            )
            #expect(Measured.page(Self.measure(roomy).phone).count == 7)
            #expect(Self.measure(roomy).scrolls.isEmpty)
        }
    }
#endif
