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
    final class GateShell {
        let app: GateApp
        let composition: AppComposition
        let stores: LedgerStores
        let router = AppRouter()
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
            host = GateHost(MainRoot(composition: composition, gate: gate, router: router))
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

        /// "Skip setup", then the root's gate followed until it shows the tabs: the root is alive meanwhile, and
        /// the tabs are all its gate can move to. Returns once `saves` programs have been saved through onboarding.
        func skipSetup(saves: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
            tap("Skip setup", sourceLocation: sourceLocation)
            await app.journal.until("programs.save done", count: saves)
            let call = Task { await gate.follow(composition, in: .active) }
            await gateObserved { gate.destination == .main }
            call.cancel()
            await call.value
            host?.settle()
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
