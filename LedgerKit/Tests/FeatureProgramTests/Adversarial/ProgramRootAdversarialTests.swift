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

    /// F11 S13 adversarial round 1: `ProgramRoot` hosted in a window (criteria 7, 9, 12 to 14). Its tasks alone
    /// run the store and the save loop; it hands the app a route once and only after the write it waits for; it
    /// announces the notice; it selects the week the app asks for, and again on a new request for the same week.
    @MainActor
    @Suite("Adversarial F11 S13 · the builder's root", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct ProgramRootAdversarialTests {
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

        @Test("Criterion 14: no active program draws the empty state from the root's own task; nothing is announced")
        func noProgram_emptyState() async throws {
            let rig = try S13Rig(program: .some(nil))
            let handed = S13Handed()
            await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.store.state == .noProgram }
            }
            #expect(handed.spoken.isEmpty)
            #expect(handed.routes.isEmpty)
        }

        @Test("Criterion 7 and 14: an observation that ends shows failed; hosted again, the root reads and shows it")
        func failed_thenHostedAgain_loads() async throws {
            let rig = try S13Rig { S13EndingPrograms(base: $0, endings: 1) }
            let handed = S13Handed()
            await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.store.state == .failed }
            }
            await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.model != nil }
            }
            #expect(rig.model?.header.name == "Upper / Lower")
        }

        @Test("Criterion 13: \"+ Add training day\"'s route reaches the app only after its write returned, and once")
        func addDay_routeAfterTheWrite_once() async throws {
            let rig = try S13Rig()
            let handed = S13Handed()
            try await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.model != nil }
                await rig.probe.hold(.updateProgram)
                rig.store.send(.addDay(name: "Day 5", weekIndex: 4))
                try await rig.probe.waitUntilHeld()
                // A route of its own, handed on while the day's write is held: the app has been handed what
                // waits by the time it arrives.
                rig.store.send(.route(.closeDay))
                await s13Until { handed.routes.contains(.closeDay) }
                #expect(handed.routes == [.closeDay], "no Day editor before its day is stored")
                await rig.probe.release()
                await s13Until { handed.routes.count == 2 }
                #expect(handed.routes == [.closeDay, .day(DayTemplateID(S13IDs.id(0)), weekIndex: 4)])
                #expect(try await rig.storedProgram()?.days.count == 5)
                // Nothing more is handed on: one more route, as a sentinel, arrives alone.
                rig.store.send(.route(.closeDay))
                await s13Until { handed.routes.count == 3 }
                #expect(handed.routes.last == .closeDay)
            }
        }

        @Test("Criterion 13: a failed write hands the app no route")
        func addDay_failedWrite_noRoute() async throws {
            let rig = try S13Rig()
            let handed = S13Handed()
            await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.model != nil }
                await rig.probe.fail(.updateProgram)
                rig.store.send(.addDay(name: "Day 5", weekIndex: 0))
                await s13Until { rig.store.notice == .saveFailed && rig.session.isIdle }
                rig.store.send(.route(.closeDay))
                await s13Until { !handed.routes.isEmpty }
                #expect(handed.routes == [.closeDay])
            }
        }

        @Test("Criterion 12: the notice is announced when it appears and when it changes, the failure's line too")
        func notice_isAnnounced() async throws {
            let rig = try S13Rig()
            let handed = S13Handed()
            await Self.hosting(S13RootHost(store: rig.store, input: S13RootInput(), handed: handed)) {
                await s13Until { rig.model != nil }
                rig.store.send(.notice(.minimumTwoWeeks))
                await s13Until { handed.spoken.count == 1 }
                rig.store.send(.notice(.weekHasLoggedSessions(weekNumber: 8)))
                await s13Until { handed.spoken.count == 2 }
                rig.store.send(.selectWeek(1))
                rig.store.send(.notice(.minimumTwoWeeks))
                await s13Until { handed.spoken.count == 3 }
                await rig.probe.fail(.updateProgram)
                rig.store.send(.rename("Refused"))
                await s13Until { handed.spoken.count == 4 }
            }
            #expect(handed.spoken == [
                "A block needs at least 2 weeks.",
                "Week 8 has logged sessions and can't be removed.",
                "A block needs at least 2 weeks.",
                "That change wasn't saved. Try again."
            ])
        }

        @Test(
            "Criterion 9: a requested week wins over today's, a new request for it selects it again, a redraw does not"
        )
        func requestedWeek_winsAndRepeats() async throws {
            let rig = try S13Rig()
            let handed = S13Handed()
            let input = S13RootInput(week: ProgramWeekRequest(number: 1, weekIndex: 6))
            await Self.hosting(S13RootHost(store: rig.store, input: input, handed: handed)) {
                await s13Until { rig.model != nil }
                #expect(rig.store.selectedWeek == 6, "asked for 6; today is in week 5 (index 4)")
                rig.store.send(.selectWeek(2))
                input.redraws += 1
                // A route handed on proves the root has drawn again since.
                rig.store.send(.route(.closeDay))
                await s13Until { handed.routes == [.closeDay] }
                #expect(rig.store.selectedWeek == 2, "the same request drawn again selects nothing")
                input.week = ProgramWeekRequest(number: 2, weekIndex: 6)
                await s13Until { rig.store.selectedWeek == 6 }
                rig.store.send(.selectWeek(3))
                input.week = ProgramWeekRequest(number: 3, weekIndex: 0)
                await s13Until { rig.store.selectedWeek == 0 }
            }
        }

        @Test("Criterion 9: a request while the program is being read is not overwritten by today's week")
        func requestDuringTheFirstRead_wins() async throws {
            let rig = try S13Rig()
            let handed = S13Handed()
            let input = S13RootInput()
            await Self.hosting(S13RootHost(store: rig.store, input: input, handed: handed)) {
                input.week = ProgramWeekRequest(number: 1, weekIndex: 7)
                await s13Until { rig.model != nil }
                await s13Until { rig.store.selectedWeek == 7 }
                #expect(rig.model?.block.chips.last?.isSelected == true)
            }
        }
    }

    /// What the root handed the app and said to VoiceOver.
    @MainActor @Observable
    final class S13Handed {
        var routes: [ProgramRoute] = []
        var spoken: [String] = []
    }

    /// What the app hands the root, changed by a test while it is hosted.
    @MainActor @Observable
    final class S13RootInput {
        var week: ProgramWeekRequest?
        var redraws = 0

        init(week: ProgramWeekRequest? = nil) {
            self.week = week
        }
    }

    struct S13RootHost: View {
        let store: ProgramStore
        let input: S13RootInput
        let handed: S13Handed

        var body: some View {
            let _ = input.redraws // swiftlint:disable:this redundant_discardable_let
            ProgramRoot(
                store: store,
                week: input.week,
                onRoute: { handed.routes.append($0) },
                announce: { handed.spoken.append($0) }
            )
            .environment(\.scenePhase, .active)
        }
    }
#endif
