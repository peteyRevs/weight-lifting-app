#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S14 adversarial round 2: the fix of F11-S14-1 (`ProgramStore.select(request:)`, a request applied once
    /// by its number), attacked through the hosted root at the root of a navigation stack: the same week asked
    /// for anew, a request that pops a pushed screen (question 2), a request before the store has loaded, the
    /// root hosted again, a week out of the block, and two requests at once.
    @MainActor
    @Suite(
        "Adversarial F11 S14 · a week request, applied once",
        .serialized,
        .tags(.feature),
        .timeLimit(.minutes(1))
    )
    struct ProgramWeekRequestAdversarialTests {
        typealias Stack = ProgramStackAdversarialTests.Stack
        typealias Pushing = ProgramStackAdversarialTests.Pushing

        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        private static func settle() async {
            for _ in 0 ..< 20 {
                await Task.yield()
            }
        }

        /// Pushes the plain screen and pops it, returning once the builder has appeared again.
        private static func pushAndPop(_ stack: Stack) async {
            let pushed = stack.pushedAppearances
            let shown = stack.builderAppearances
            stack.path = [1]
            await s13Until { stack.pushedAppearances > pushed }
            stack.path = []
            await s13Until { stack.builderAppearances > shown }
            await settle()
        }

        @Test("A new request for the week asked for before selects it again, and is then kept like the first")
        func sameWeek_newNumber_selectsAgain_thenIsKept() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
                stack.week = ProgramWeekRequest(number: 2, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(6))
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 6)
            }
        }

        @Test("Question 2: a request that pops a pushed screen selects its week, and a later pop keeps the pick")
        func requestWhilePushed_popsAndSelects() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
                stack.path = [1]
                await s13Until { stack.pushedAppearances == 1 }
                // What `AppRouter.editProgramWeek` does: the stack emptied and a new request, in one go.
                stack.path = []
                stack.week = ProgramWeekRequest(number: 2, weekIndex: 3)
                await s13Until { stack.builderAppearances == 2 }
                await Self.settle()
                #expect(rig.store.selectedWeek == 3)
                rig.store.send(.selectWeek(6))
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 6)
            }
        }

        @Test("A request handed in before the store has loaded wins over the week that holds today, once")
        func requestBeforeLoad_winsOverToday() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                #expect(rig.store.selectedWeek == 1, "not week 5, which holds today")
                rig.store.send(.selectWeek(5))
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 5)
            }
        }

        @Test("The root hosted again over the same store (a new run of its tasks) keeps the week picked")
        func hostedAgain_keepsThePick() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil && rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
            }
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { stack.builderAppearances == 2 }
                await Self.settle()
                #expect(rig.store.selectedWeek == 5)
            }
        }

        @Test("The active program gone and back: the old request is not applied again")
        func programGoneAndBack_doesNotReapply() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            try await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
                let program = try #require(try await rig.storedProgram())
                try await rig.memory.programs.delete(program.id)
                await s13Until { rig.store.state == .noProgram }
                try await rig.memory.programs.save(program)
                try await rig.memory.programs.setActive(program.id)
                await s13Until { rig.model != nil }
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 5)
            }
        }

        @Test("A request for a week past the block is kept raw and drawn as the last week; the pick then holds")
        func requestOutOfRange_drawsTheLastWeek() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 20)
                await s13Until { rig.store.selectedWeek == 20 }
                #expect(rig.model?.week.title.hasPrefix("WEEK 8") == true, "the last week (the seed's deload)")
                rig.store.send(.selectWeek(2))
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 2)
            }
        }

        @Test("Two requests in one go: the second's week is selected, and neither comes back after a pop")
        func twoRequestsAtOnce_theSecondWins() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                stack.week = ProgramWeekRequest(number: 2, weekIndex: 3)
                await s13Until { rig.store.selectedWeek == 3 }
                rig.store.send(.selectWeek(6))
                await Self.pushAndPop(stack)
                #expect(rig.store.selectedWeek == 6)
            }
        }
    }
#endif
