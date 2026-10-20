#if os(iOS)
    import Foundation
    @testable import LedgerAppKit
    import LedgerDomain
    import Testing

    /// F08 S3 adversarial round 2 (G2), criteria 3 and 4 after the fix of F8-S3-1: the tabs a lifter reaches
    /// after onboarding open on Today with every stack empty, the second and the third time as the first,
    /// whatever tab was selected and whatever was pushed when the program went away. Each run of onboarding
    /// saves through onboarding's own buttons into the real database.
    ///
    /// Round 1 held this with one root alive throughout (`secondOnboarding_landsOnToday`, which found the bug
    /// and passed unedited after the fix). That shape made onboarding's second store outside the test's
    /// dependencies (F8-S3-4), so it is gone: here each return to onboarding is a new `MainRoot` over the
    /// router the test keeps (`GateShell`).
    /// Port of F08 S2/S3: Today is read as `GateShown.isTabs` (its title is inside its scroll view on `main`), and
    /// the shell starts over with a new router (ruling R4), which `GateShell` keeps.
    @Suite("Adversarial F08 S3 · the shell starts over with onboarding", .serialized, .timeLimit(.minutes(1)))
    struct AppRootResetAdversarialTests {
        /// What each tab's root reads outside scroll views. Port of F08 S2/S3, after merging F11 S14: the Program
        /// tab is the builder, over the program onboarding saved, whose page is inside its scroll view, so it reads
        /// nothing there (as Today does); Library and History are still placeholders with their titles.
        static let titles: [AppTab: [String]] = [.program: [], .library: ["Library"], .history: ["History"]]

        @Test(
            "A second and a third onboarding land on Today, whatever tab the program went away under",
            arguments: [[AppTab.program, .history], [.library, .program], [.history, .library]]
        )
        func laterOnboardings_landOnToday(leftOn tabs: [AppTab]) async throws {
            let app = GateApp("laterOnboardings\(tabs)")
            defer { app.remove() }
            try await GateShell.run(app) { shell in
                await shell.open()
                #expect(shell.shown.labels == ["Continue", "Skip setup"])
                await shell.skipSetup(saves: 1)
                #expect(shell.shown.isTabs, "\(shell.shown)")
                for (run, tab) in tabs.enumerated() {
                    shell.select(tab)
                    #expect(shell.shown.labels == Self.titles[tab] ?? ["?"], "control: the lifter is on \(tab)")
                    #expect(shell.router.selectedTab == tab)
                    try await shell.deleteTheProgramAndReopen()
                    let onboarding = shell.shown
                    #expect(onboarding.isOnboarding, "\(onboarding)")
                    #expect(onboarding.labels == ["Continue", "Skip setup"], "onboarding starts on step 1")
                    #expect(shell.isRouterAtItsStart, "the shell starts over when onboarding appears")
                    await shell.skipSetup(saves: run + 2)
                    let tabsAgain = shell.shown
                    #expect(tabsAgain.tabBars == 1)
                    #expect(tabsAgain.isTabs, "onboarding \(run + 2) left \(tab) selected: \(tabsAgain)")
                }
                let stored = try await shell.stores.queue.read { database in
                    try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM program WHERE deleted_at IS NULL") ?? -1
                }
                #expect(stored == 1, "one live program after three runs of onboarding")
                // Each onboarding screen read the unit once when it appeared and once for its save.
                #expect(app.journal.count(of: "settings.load begins") == 6, "settings reads through the probe")
            }
        }

        @Test(
            "A screen pushed when the program goes away is gone after onboarding, under Today and under another tab",
            arguments: [AppTab.today, .library]
        )
        func pushedScreen_isGoneAfterOnboarding(under tab: AppTab) async throws {
            let app = GateApp("pushedScreen\(tab)")
            defer { app.remove() }
            try await GateShell.run(app) { shell in
                await shell.open()
                await shell.skipSetup(saves: 1)
                shell.pushSettings(in: tab)
                #expect(shell.router[path: tab] == [.settings], "control: Settings is pushed")
                #expect(shell.router.selectedTab == tab)
                let pushed = shell.shown
                #expect(pushed.labels.contains("Settings"), "control: Settings is on screen: \(pushed)")
                try await shell.deleteTheProgramAndReopen()
                #expect(shell.shown.isOnboarding)
                #expect(shell.isRouterAtItsStart, "the pushed screen and the selection were kept")
                await shell.skipSetup(saves: 2)
                #expect(shell.shown.isTabs, "\(shell.shown)")
                if tab != .today {
                    shell.select(tab)
                    #expect(shell.shown.labels == Self.titles[tab] ?? ["?"], "the tab's own root, not Settings")
                }
                #expect(shell.areStacksEmpty)
            }
        }

        @Test("A root that opens on the tabs, and one that returns to them with no onboarding between, keep the shell")
        func noOnboardingBetween_theShellIsKept() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateShell.run(app) { shell in
                await shell.open()
                await shell.skipSetup(saves: 1)
                shell.select(.history)
                shell.pushSettings(in: .history)
                shell.close()
                await shell.open() // the same program, a new root: nothing asked the shell to start over
                #expect(shell.router.selectedTab == .history)
                #expect(shell.router[path: .history] == [.settings], "a reset without onboarding lost the stack")
                #expect(shell.shown.labels.contains("Settings"), "\(shell.shown)")
            }
        }
    }
#endif
