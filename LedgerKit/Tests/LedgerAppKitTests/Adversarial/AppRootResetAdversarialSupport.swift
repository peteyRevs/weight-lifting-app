#if os(iOS)
    import Foundation
    import GRDB
    @testable import LedgerAppKit
    import LedgerDomain
    import LedgerPersistence
    import SwiftUI
    import Testing

    /// The shell as `MainRoot` draws it over a router the test keeps, one root at a time, each over a gate of
    /// its own that has already answered when the root is made.
    ///
    /// This is how the hosted suites return to onboarding (the rule at `GateRootScene`). `MainRoot` runs no
    /// task of its own, so its gate moves only while the test follows it; a root is taken down before the
    /// program goes away; and the next root gets a new gate, so nothing that is left of the old root can see a
    /// gate move to onboarding. What must last from one root to the next is the router, which `MainRoot` takes
    /// for this, and the database.
    ///
    /// Port of F08 S2/S3 (ruling R4): the shell now starts over with a new router when onboarding appears, made
    /// by `MainRoot`'s `newRouter`, instead of resetting the one it has. The shell hands each root a `newRouter`
    /// that keeps the router it makes, so `router` is always the one the screen shows.
    final class GateShell {
        let app: GateApp
        let composition: AppComposition
        let stores: LedgerStores
        private(set) var router = AppRouter()
        private(set) var gate = RootGate()
        private var host: GateHost?

        init(_ app: GateApp) throws {
            self.app = app
            composition = app.booted()
            stores = try #require(composition.stores)
        }

        /// Boots `app` and runs `body` with its shell, inside the dependencies onboarding's store reads.
        static func run(_ app: GateApp, _ body: (GateShell) async throws -> Void) async throws {
            let shell = try GateShell(app)
            try await withGateDependencies(shell.composition, app.journal) {
                defer { shell.close() }
                try await body(shell)
            }
        }

        /// A new root over a new gate that has followed the store to its answer: its first layout, in the
        /// caller's task, draws the screen.
        func open() async {
            close()
            gate = await GateAnswers.followed(composition)
            host = GateHost(MainRoot(composition: composition, gate: gate, router: router) { [weak self] in
                let next = AppRouter()
                self?.router = next
                return next
            })
        }

        /// Takes the root down and lets go of it.
        func close() {
            host?.close()
            host = nil
        }

        var shown: GateShown {
            host?.shown ?? GateShown(labels: ["no root"], tabBars: -1, scrollViews: -1)
        }

        /// A double tap on the pinned button VoiceOver reads as `label`.
        func tap(_ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
            let before = shown
            let isActivated = host?.activate(label) ?? false
            #expect(isActivated, "no enabled \"\(label)\" in \(before)", sourceLocation: sourceLocation)
        }

        /// A tap on the tab bar's button for `tab`.
        func select(_ tab: AppTab, sourceLocation: SourceLocation = #_sourceLocation) {
            let index = AppTab.allCases.firstIndex(of: tab) ?? -1
            let isTapped = host?.tapTab(at: index) ?? false
            #expect(isTapped, "no tab bar button \(index)", sourceLocation: sourceLocation)
        }

        /// Pushes Settings on `tab`'s stack through the router, as a route does, and lets SwiftUI apply it.
        func pushSettings(in tab: AppTab) {
            router.open(.settings, in: tab)
            host?.settle()
        }

        /// "Skip setup", then, once `saves` programs have been saved through onboarding, a new root over a gate
        /// that has answered the tabs.
        ///
        /// Port of F08 S2/S3 (ruling B): the real tabs are drawn here, and `main`'s Today has a store, so no root
        /// is alive while its gate can move to `.main` (the rule `GateRootScene` keeps for onboarding, F8-S3-4).
        /// The root that saved is never followed, so it stays on onboarding until it is taken down; the new root
        /// keeps `router`, the one the shell started over with when onboarding appeared.
        func skipSetup(saves: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
            tap("Skip setup", sourceLocation: sourceLocation)
            await app.journal.until("programs.save done", count: saves)
            await open()
            #expect(gate.destination == .main, "the saved program shows the tabs", sourceLocation: sourceLocation)
        }

        /// The active program goes away with no root alive (what the gate sees of Settings' "Delete all data",
        /// F14), then a new root shows what the store holds now.
        func deleteTheProgramAndReopen() async throws {
            close()
            let program = try #require(try await stores.programs.active())
            try await stores.programs.delete(program.id)
            await open()
        }

        /// Whether no tab has a screen pushed.
        var areStacksEmpty: Bool {
            AppTab.allCases.allSatisfy { router[path: $0].isEmpty }
        }

        /// Whether the router is as the shell opens: Today selected and every stack empty.
        var isRouterAtItsStart: Bool {
            router.selectedTab == .today && areStacksEmpty
        }
    }
#endif
