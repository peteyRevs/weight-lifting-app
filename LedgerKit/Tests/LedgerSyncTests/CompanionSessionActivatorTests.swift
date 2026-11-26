#if canImport(WatchConnectivity)
    import LedgerDomain
    @testable import LedgerSync
    import Testing
    import WatchConnectivity

    /// `CompanionSessionActivator` on a stand-in session: no real `WCSession` is activated (testing-strategy §3).
    @Suite("Companion session activator", .timeLimit(.minutes(1)))
    struct CompanionSessionActivatorTests {
        final class StandInSession: CompanionSession {
            weak var delegate: (any WCSessionDelegate)?
            var isReachable = false
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

        @Test("As the session's one delegate it reports reachability to the transport and hands it each message")
        func delegate_feedsTheTransport() async throws {
            let activator = CompanionSessionActivator()
            var link = activator.transport.link.makeAsyncIterator()
            var incoming = activator.transport.incoming.makeAsyncIterator()
            #expect(await link.next() == false)
            let session = StandInSession()
            session.isReachable = true
            activator.reachabilityChanged(of: session)
            #expect(await link.next() == true)
            let frame = WireFrame.handshake(workoutID: Sample.session.id, contiguousSeq: [:])
            try activator.session(WCSession.default, didReceiveMessageData: #require(WireCodec.encode(frame).first))
            #expect(await incoming.next() == frame)
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
