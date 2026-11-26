#if canImport(WatchConnectivity)
    import os
    import WatchConnectivity

    /// Activates the default `WCSession` at launch with this as its delegate, and logs what the session reports
    /// (architecture §4, §8). It is the session's one delegate on both devices: it reports the peer's reachability
    /// and hands each message to `transport`, the live workout's WatchConnectivity channel (F17 S7). F19 builds the
    /// companion transport on it.
    ///
    /// `WCSession` holds its delegate weakly: the composition root keeps the activator for the app's lifetime.
    /// WatchConnectivity calls the delegate on a background queue; nothing here is mutable.
    public final class CompanionSessionActivator: NSObject, WCSessionDelegate, Sendable {
        /// The live workout's frames over `WCSession.default`'s messages.
        public let transport: WatchConnectivityTransport
        private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "sync")

        override public convenience init() {
            self.init(transport: WatchConnectivityTransport(session: DefaultMessageSession()))
        }

        init(transport: WatchConnectivityTransport) {
            self.transport = transport
            super.init()
        }

        /// Activates the default session; where WatchConnectivity is unsupported (an iPad) it logs and stops.
        public func activate() {
            activate(WCSession.isSupported() ? WCSession.default : nil)
        }

        func activate(_ session: (some CompanionSession)?) {
            guard let session else {
                logger.notice("WatchConnectivity is not supported on this device")
                return
            }
            session.delegate = self
            session.activate()
        }

        public func session(
            _ session: WCSession,
            activationDidCompleteWith state: WCSessionActivationState,
            error: (any Error)?
        ) {
            if let error {
                logger.error("WCSession activation failed: \(String(describing: error), privacy: .public)")
            } else {
                logger.info("WCSession activation completed in state \(state.rawValue, privacy: .public)")
            }
            reachabilityChanged(of: session)
        }

        public func sessionReachabilityDidChange(_ session: WCSession) {
            reachabilityChanged(of: session)
        }

        func reachabilityChanged(of session: some CompanionSession) {
            transport.reachabilityChanged(session.isReachable)
        }

        public func session(_: WCSession, didReceiveMessageData messageData: Data) {
            transport.received(messageData)
        }

        #if os(iOS)
            public func sessionDidBecomeInactive(_: WCSession) {
                logger.info("WCSession became inactive")
            }

            /// The lifter switched to another watch: activate again so the session reaches the new one.
            public func sessionDidDeactivate(_ session: WCSession) {
                reactivate(session)
            }

            func reactivate(_ session: some CompanionSession) {
                logger.info("WCSession deactivated; activating it for the current watch")
                session.activate()
            }
        #endif
    }

    /// What the activator needs of a `WCSession`, so its tests can hand it a stand-in rather than activate the
    /// real one (testing-strategy §3: no WatchConnectivity in tests).
    protocol CompanionSession: AnyObject {
        var delegate: (any WCSessionDelegate)? { get set }
        var isReachable: Bool { get }
        func activate()
    }

    extension WCSession: CompanionSession {}

    /// `WCSession.default` as the WatchConnectivity transport's `MessageSession`: the adapter is these two calls,
    /// and the rules are `WatchConnectivityTransport`'s, tested over a stand-in. The session is looked up on each
    /// call rather than kept, since `WCSession` is not `Sendable`.
    struct DefaultMessageSession: MessageSession {
        var isReachable: Bool {
            WCSession.default.isReachable
        }

        func sendMessageData(_ data: Data, failed: @escaping @Sendable (any Error) -> Void) {
            WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: failed)
        }
    }
#endif
