#if canImport(WatchConnectivity)
    import Foundation
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

        /// A received file at `url`, as the session hands one over.
        final class StandInFile: WCSessionFile {
            let url: URL

            init(_ url: URL) {
                self.url = url
            }

            override var fileURL: URL {
                url
            }
        }

        /// A finished transfer of the file at `url`.
        final class StandInFileTransfer: WCSessionFileTransfer {
            let url: URL

            init(_ url: URL) {
                self.url = url
            }

            override var file: WCSessionFile {
                StandInFile(url)
            }
        }

        static func payload(_ payload: some CompanionPayload) throws -> [String: Any] {
            try [WCCompanionTransport.payloadKey: CompanionCodec.encode(payload)]
        }

        @Test("It hands each application context and user info that arrives to the companion transport")
        func delegate_feedsTheCompanionContextAndRecords() async throws {
            let activator = CompanionSessionActivator()
            try activator.session(WCSession.default, didReceiveApplicationContext: Self.payload(Self.context))
            try activator.session(WCSession.default, didReceiveUserInfo: Self.payload(Self.record))
            let contexts = await FakeLiveWorkoutTransportTests.next(1, of: activator.companion.receivedContext)
            #expect(contexts == [Self.context])
            let records = await FakeLiveWorkoutTransportTests.next(1, of: activator.companion.receivedRecords)
            #expect(records == [Self.record])
        }

        @Test("It reads each file that arrives before returning, when the session deletes it")
        func delegate_readsEachFileBeforeReturning() async throws {
            let activator = CompanionSessionActivator()
            let url = URL.temporaryDirectory.appending(path: "CompanionSessionActivatorTests-\(UUID().uuidString)")
            try CompanionCodec.encode(CompanionFile.workoutLog(Self.record)).write(to: url)
            activator.session(WCSession.default, didReceive: StandInFile(url))
            try FileManager.default.removeItem(at: url)
            let files = await FakeLiveWorkoutTransportTests.next(1, of: activator.companion.receivedFiles)
            #expect(files == [.workoutLog(Self.record)])
        }

        @Test("A finished file transfer removes the companion transport's file")
        func delegate_finishedTransfer_removesTheFile() async throws {
            let session = StandInCompanionSession()
            let outbox = URL.temporaryDirectory.appending(path: "CompanionSessionActivatorTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: outbox) }
            let activator = CompanionSessionActivator(
                transport: WatchConnectivityTransport(session: StandInMessageSession()),
                companion: WCCompanionTransport(session: session, outbox: outbox, log: { _ in })
            )
            try await activator.companion.transfer(.workoutLog(Self.record))
            let url = try #require(session.state.withLock(\.files).first?.url)
            activator.session(WCSession.default, didFinish: StandInFileTransfer(url), error: nil)
            #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }

        @Test("Live messages and companion payloads never cross: each side drops the other's")
        func liveAndCompanion_doNotCrossTalk() async throws {
            let activator = CompanionSessionActivator()
            let frame = WireFrame.handshake(workoutID: Sample.session.id, contiguousSeq: [:])
            let live = try #require(WireCodec.encode(frame).first)
            try activator.session(WCSession.default, didReceiveMessageData: CompanionCodec.encode(Self.record))
            activator.session(WCSession.default, didReceiveApplicationContext: [WCCompanionTransport.payloadKey: live])
            activator.session(WCSession.default, didReceiveUserInfo: [WCCompanionTransport.payloadKey: live])
            activator.session(WCSession.default, didReceiveMessageData: live)
            try activator.session(WCSession.default, didReceiveApplicationContext: Self.payload(Self.context))
            try activator.session(WCSession.default, didReceiveUserInfo: Self.payload(Self.record))
            #expect(await FakeLiveWorkoutTransportTests.next(1, of: activator.transport.incoming) == [frame])
            let contexts = await FakeLiveWorkoutTransportTests.next(1, of: activator.companion.receivedContext)
            #expect(contexts == [Self.context])
            let records = await FakeLiveWorkoutTransportTests.next(1, of: activator.companion.receivedRecords)
            #expect(records == [Self.record])
        }

        static let context = FakeCompanionTransportTests.context(5)
        static let record = FakeCompanionTransportTests.record(5)

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
