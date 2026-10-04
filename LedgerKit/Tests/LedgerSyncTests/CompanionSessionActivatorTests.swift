#if canImport(WatchConnectivity)
    @testable import LedgerSync
    import Testing
    import WatchConnectivity

    /// `CompanionSessionActivator` on a stand-in session: no real `WCSession` is activated (testing-strategy §3).
    @Suite("Companion session activator")
    struct CompanionSessionActivatorTests {
        final class StandInSession: CompanionSession {
            weak var delegate: (any WCSessionDelegate)?
            private(set) var activations = 0

            func activate() {
                activations += 1
            }
        }

        @Test("activate makes the activator the session's delegate, then activates it once")
        func activate_setsTheDelegate_thenActivates() {
            let activator = CompanionSessionActivator()
            let session = StandInSession()
            activator.activate(session)
            #expect(session.delegate === activator)
            #expect(session.activations == 1)
        }

        @Test("Without WatchConnectivity support there is nothing to activate")
        func activate_unsupported_doesNothing() {
            CompanionSessionActivator().activate(StandInSession?.none)
        }

        @Test("The activation callbacks only log, with or without an error")
        func activationCallbacks_log() {
            let activator = CompanionSessionActivator()
            activator.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
            activator.session(
                WCSession.default,
                activationDidCompleteWith: .notActivated,
                error: WCError(.sessionNotSupported)
            )
            #if os(iOS)
                activator.sessionDidBecomeInactive(WCSession.default)
            #endif
        }

        #if os(iOS)
            @Test("A deactivated session (the lifter switched watches) is activated again")
            func deactivation_activatesAgain() {
                let session = StandInSession()
                CompanionSessionActivator().reactivate(session)
                #expect(session.activations == 1)
            }
        #endif
    }
#endif
