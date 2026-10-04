#if canImport(WatchConnectivity)
    import os
    import WatchConnectivity

    /// Activates the default `WCSession` at launch with this as its delegate, and logs what the session reports
    /// (architecture §4, §8). F19 builds the companion transport on it.
    ///
    /// `WCSession` holds its delegate weakly: the composition root keeps the activator for the app's lifetime.
    /// WatchConnectivity calls the delegate on a background queue; nothing here is mutable.
    public final class CompanionSessionActivator: NSObject, WCSessionDelegate, Sendable {
        private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "sync")

        override public init() {
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
            _: WCSession,
            activationDidCompleteWith state: WCSessionActivationState,
            error: (any Error)?
        ) {
            if let error {
                logger.error("WCSession activation failed: \(String(describing: error), privacy: .public)")
            } else {
                logger.info("WCSession activation completed in state \(state.rawValue, privacy: .public)")
            }
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
        func activate()
    }

    extension WCSession: CompanionSession {}
#endif
