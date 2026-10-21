#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F08 S2 close-out (round 2), criterion 10 as revised: "going to another step starts that step at its top".
    /// The real root in a window of a phone's size and safe area; its one scroll view is found under the
    /// hosting view and moved, and the step is changed through the store, as a tap on a control changes it.
    /// Every pair of steps, both ways, from the page's end and from its middle, on the narrowest and the widest
    /// phone at three accessibility sizes; and what must not move the page.
    ///
    /// **Two ways of moving the page.** A test process cannot touch the screen. SwiftUI takes a scroll for the
    /// lifter's when the scroll view's delegate hears a drag begin and end around it (measured on iOS 27.0:
    /// `ScrollPosition.isPositionedByUser` turns true), and for nobody's when the offset is only set (it stays
    /// false: what VoiceOver's or Voice Control's "scroll down" does). `Move.drag` makes those delegate calls;
    /// `Move.set` only sets the offset. A step change must start at the top after either.
    ///
    /// **A turn of the main queue after every tap.** SwiftUI applies a step change's "to the top" once more on
    /// the main queue's next turn (measured: an offset set in the same turn as the change is undone there, with
    /// no change of state at all). A finger cannot scroll within the turn of the tap before it, so each tap
    /// here is followed by a turn before the page is moved, as on a phone.
    @Suite("Adversarial F08 S2 close-out · a new step starts at its top", .timeLimit(.minutes(1)))
    struct OnboardingScrollAdversarialTests {
        /// How the page is moved.
        nonisolated enum Move: String, Sendable {
            case drag, set
        }

        /// A phone, a text size and a way of moving the page.
        nonisolated struct Setting: Sendable, CustomStringConvertible {
            let phone: PhoneFrame
            let size: DynamicTypeSize
            let move: Move

            var description: String {
                "\(phone), \(size), \(move)"
            }

            /// Whether every step is longer than the screen here: on the narrowest phone above the first
            /// accessibility size. (On the widest at the first, every step fits and nothing can be scrolled.)
            var isTight: Bool {
                phone.width < 400 && size != .accessibility1
            }

            /// On the hosted PR run, the first accessibility size (where nothing scrolls on the widest phone) and
            /// the largest (F08 S2/S3 port, criterion 25).
            static let sizes = TestSweep.sizes(
                [.accessibility1, .accessibility3, .accessibility5],
                also: [.accessibility1]
            )

            static let all: [Setting] = [PhoneFrame.smallest, .widest].flatMap { phone in
                sizes.flatMap { size in
                    [Move.drag, .set].map { Setting(phone: phone, size: size, move: $0) }
                }
            }
        }

        /// The hosted root, its store and its scroll view.
        final class Stage {
            let scene: AdversarialScene
            let host: PhoneHost
            let move: Move

            init(
                _ setting: Setting,
                settings: Settings = .default,
                prepare: (AdversarialScene) -> Void = { _ in }
            ) throws {
                scene = try AdversarialScene(.seeded(settings))
                prepare(scene)
                move = setting.move
                host = PhoneHost(
                    OnboardingRoot(store: scene.store, prepareRetry: {}),
                    on: setting.phone,
                    SnapshotAppearance(.dark, setting.size)
                )
            }

            /// Lays the screen out until SwiftUI has applied a change and what answered it.
            func settle() {
                for _ in 0 ..< 3 {
                    host.layout()
                }
            }

            func scrollView() throws -> UIScrollView {
                let found = host.scrollViews
                #expect(found.count == 1, "the screen is its pinned part and one scroll view")
                return try #require(found.first)
            }

            /// How far the page is from its top.
            func offset() throws -> CGFloat {
                let scroll = try scrollView()
                return scroll.contentOffset.y + scroll.adjustedContentInset.top
            }

            /// How far the page can go.
            func range() throws -> CGFloat {
                let scroll = try scrollView()
                let insets = scroll.adjustedContentInset
                return max(scroll.contentSize.height + insets.top + insets.bottom - scroll.bounds.height, 0)
            }

            /// Moves the page to `share` of its way down (1 is its end), and returns where that is.
            @discardableResult
            func scroll(to share: CGFloat) throws -> CGFloat {
                let scroll = try scrollView()
                let target = try (range() * share).rounded()
                let point = CGPoint(x: scroll.contentOffset.x, y: target - scroll.adjustedContentInset.top)
                if move == .drag {
                    scroll.delegate?.scrollViewWillBeginDragging?(scroll)
                    scroll.setContentOffset(point, animated: false)
                    scroll.delegate?.scrollViewDidEndDragging?(scroll, willDecelerate: false)
                } else {
                    scroll.setContentOffset(point, animated: false)
                }
                settle()
                #expect(try abs(offset() - target) < 1, "control: the page is where it was put")
                return target
            }

            /// The taps, one after the other in one turn of the main queue, then the turn that follows them.
            func send(_ actions: OnboardingAction...) async {
                actions.forEach(scene.store.send)
                settle()
                await turn()
            }

            /// One turn of the main queue, and the layout it leaves to do. An event, not a wait: the
            /// continuation is resumed by the queue's next block.
            func turn() async {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                settle()
            }
        }

        /// Each pair of neighbouring steps, both ways, and back again.
        nonisolated static let walk: [(action: OnboardingAction, lands: OnboardingState.Step)] = [
            (.advance, .days), (.advance, .program), (.back, .days), (.back, .goal), (.advance, .days),
            (.back, .goal)
        ]
    }

    /// The walks.
    extension OnboardingScrollAdversarialTests {
        @Test(
            "Each step change, both ways, starts the new step at its top from the end of the last",
            arguments: Setting.all
        )
        func stepChange_fromTheEnd_startsAtTheTop(_ setting: Setting) async throws {
            let stage = try Stage(setting)
            defer { stage.host.close() }
            await stage.turn()
            #expect(try abs(stage.offset()) < 1, "the screen opens at its top")
            var scrolled = 0
            for (action, step) in Self.walk {
                if try stage.range() > 1 {
                    try stage.scroll(to: 1)
                    scrolled += 1
                }
                await stage.send(action)
                #expect(stage.scene.store.state.step == step)
                let offset = try stage.offset()
                #expect(abs(offset) < 1, "\(step) opens \(offset) pt down after \(action)")
            }
            if setting.isTight {
                #expect(scrolled == Self.walk.count, "control: every change began at a page's end, not \(scrolled)")
            }
        }

        @Test(
            "From the middle of a page, and two steps in one go, the new step still starts at its top",
            arguments: [Move.drag, .set]
        )
        func stepChange_fromTheMiddleAndTwoAtOnce_startsAtTheTop(_ move: Move) async throws {
            let stage = try Stage(Setting(phone: .smallest, size: .accessibility5, move: move))
            defer { stage.host.close() }
            await stage.turn()
            for (action, step) in Self.walk {
                let put = try stage.scroll(to: 0.5)
                #expect(put > 50, "control: the middle is well down the page")
                await stage.send(action)
                #expect(stage.scene.store.state.step == step)
                #expect(try abs(stage.offset()) < 1, "\(step) after \(action)")
            }
            try stage.scroll(to: 1)
            await stage.send(.advance, .advance)
            #expect(stage.scene.store.state.step == .program)
            #expect(try abs(stage.offset()) < 1, "two Continues before a layout")
            try stage.scroll(to: 1)
            await stage.send(.back, .back)
            #expect(stage.scene.store.state.step == .goal)
            #expect(try abs(stage.offset()) < 1, "two Backs before a layout")
        }

        @Test(
            "What changes no step moves no page: a pick, a tap at an end of the steps, a save under way and done",
            arguments: [Move.drag, .set]
        )
        func noStepChange_leavesThePageWhereItIs(_ move: Move) async throws {
            let hold = Checkpoint()
            let stage = try Stage(Setting(phone: .smallest, size: .accessibility3, move: move)) {
                $0.programs.script.next(.hold(hold))
            }
            defer { stage.host.close() }
            await stage.turn()
            let onGoal = try stage.scroll(to: 1)
            await stage.send(.pickGoal(.consistency))
            #expect(try abs(stage.offset() - onGoal) < 1, "a pick on step 1")
            await stage.send(.back)
            #expect(try abs(stage.offset() - onGoal) < 1, "Back on step 1 goes nowhere")
            await stage.send(.advance)
            let onDays = try stage.scroll(to: 0.6)
            await stage.send(.pickDays(.six))
            #expect(try abs(stage.offset() - onDays) < 1, "a pick on step 2")
            await stage.send(.advance)
            let onProgram = try stage.scroll(to: 1)
            await stage.send(.advance)
            #expect(try abs(stage.offset() - onProgram) < 1, "Continue's action on the last step goes nowhere")
            // "Start training": the root's task runs the save, which is held inside the write.
            await stage.send(.startTraining)
            await hold.arrivals()
            stage.settle()
            #expect(stage.scene.store.state.phase == .saving)
            #expect(try abs(stage.offset() - onProgram) < 1, "a save under way")
            await stage.send(.back)
            #expect(stage.scene.store.state.step == .program, "locked while it saves")
            #expect(try abs(stage.offset() - onProgram) < 1)
            hold.open()
            await observed { stage.scene.store.state.phase == .saved }
            stage.settle()
            #expect(try abs(stage.offset() - onProgram) < 1, "the save ending")
        }

        @Test(
            "The failure appearing, Back being locked and the sentence going away leave the page where it is",
            arguments: [Move.drag, .set]
        )
        func failureShown_backIsLocked_andThePageStays(_ move: Move) async throws {
            let stage = try Stage(Setting(phone: .smallest, size: .accessibility3, move: move)) {
                $0.programs.script.next(.fail("write"))
            }
            defer { stage.host.close() }
            await stage.turn()
            await stage.send(.pickGoal(.strength), .advance, .pickDays(.five), .advance)
            let put = try stage.scroll(to: 0.5)
            stage.scene.store.send(.startTraining)
            await observed { stage.scene.store.state.phase == .failed }
            stage.settle()
            let whenFailed = try stage.offset()
            #expect(abs(whenFailed - put) < 1, "the failure appearing moved the page from \(put) to \(whenFailed)")
            let locked = OnboardingState(step: .program, goal: .strength, days: .five, phase: .failed)
            await stage.send(.back, .pickGoal(.both), .pickDays(.three), .advance)
            #expect(stage.scene.store.state == locked, "criterion 7: the picks and Back are locked")
            #expect(try abs(stage.offset() - whenFailed) < 1)
            stage.scene.store.send(.retry)
            await observed { stage.scene.store.state.phase == .saved }
            stage.settle()
            #expect(stage.scene.store.state.step == .program)
            #expect(try abs(stage.offset() - whenFailed) < 1, "the sentence going away moved the page")
            try await stage.scene.expectOneProgram(goal: .strength, days: .five, offered: 2)
        }

        @Test(
            "The unit arriving while step 3 is read rewrites its sentence and leaves the page where it is",
            arguments: [Move.drag, .set]
        )
        func unitLoaded_onStepThree_leavesThePage(_ move: Move) async throws {
            let hold = Checkpoint()
            let setting = Setting(phone: .smallest, size: .accessibility3, move: move)
            let stage = try Stage(setting, settings: Fixtures.settingsKg) { $0.settings.script.next(.hold(hold)) }
            defer { stage.host.close() }
            await hold.arrivals()
            await stage.send(.advance, .advance)
            let put = try stage.scroll(to: 1)
            #expect(put > 100, "control: step 3 is longer than the screen here")
            #expect(stage.scene.store.model.body == BriefCopy.programBody(.four, .lb), "control: not read yet")
            hold.open()
            await observed { stage.scene.store.state.units == .kg }
            stage.settle()
            #expect(stage.scene.store.model.body == BriefCopy.programBody(.four, .kg))
            #expect(try abs(stage.offset() - put) < 1, "the unit arriving moved the page from \(put)")
        }
    }
#endif
