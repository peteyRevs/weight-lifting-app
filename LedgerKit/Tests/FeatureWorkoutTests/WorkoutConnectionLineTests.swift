@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F17 S8, criterion 12: the header's line about the watch. "Watch not connected — logging continues" while the
/// transport is reconnecting, and no line in any other state; the line disables nothing. The store hears the
/// connection for as long as the cover is up, and each test waits by observing the store, never by time.
@MainActor
@Suite("Workout connection line", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutConnectionLineTests {
    typealias Scene = WorkoutScene

    static let line = "Watch not connected — logging continues"

    @Test("Only reconnecting has a line: connected, degraded, solo and nothing heard yet have none")
    func line_onlyWhileReconnecting() {
        #expect(WorkoutPresentation.connectionLine(.reconnecting) == Self.line)
        let quiet: [LiveConnectionState?] = [
            nil, .solo, .connected(.mirroring), .connected(.watchConnectivity), .degraded(.mirroring)
        ]
        for connection in quiet {
            #expect(WorkoutPresentation.connectionLine(connection) == nil, "\(String(describing: connection))")
        }
    }

    @Test("The line changes nothing else: the header's buttons and every control of the page stay enabled")
    func line_disablesNothing() throws {
        let state = try WorkoutPreview.minutes.workout()
        let screen = { (connection: LiveConnectionState?) in
            WorkoutPresentation.screen(
                .loaded(state), isBusy: false, locale: Fixtures.locale, calendar: Fixtures.calendar,
                connection: connection
            )
        }
        let reconnecting = screen(.reconnecting)
        let quiet = screen(nil)
        var withoutTheLine = try #require(reconnecting.header)
        #expect(withoutTheLine.connection == Self.line)
        #expect(withoutTheLine.isEnabled)
        withoutTheLine.connection = nil
        let isTheSameHeader = withoutTheLine == quiet.header
        #expect(isTheSameHeader, "the line is the one difference in the header")
        let isTheSamePage = reconnecting.page == quiet.page && quiet.page != nil
        #expect(isTheSamePage, "the page, and whether its controls answer, do not read the connection")
    }

    @Test("The store hears each change: the line shows while reconnecting, a tap is applied meanwhile, and it goes")
    func store_followsTheConnection() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let connection = FakeLiveConnection(.connected(.mirroring), scripted: true)
        let store = scene.store { $0.liveConnection = connection }
        let follow = Task { await store.follow() }
        let pump = Task { await store.pump() }
        await eventually { store.shown != nil }
        #expect(store.connection == nil, "nothing is heard before the cover listens")
        let hear = Task { await store.followConnection() }
        await eventually { store.connection == .connected(.mirroring) }
        #expect(store.model.header?.connection == nil)

        await connection.change(to: .reconnecting)
        await eventually { store.connection == .reconnecting }
        #expect(store.model.header?.connection == Self.line)
        #expect(store.model.header?.isEnabled == true)
        let first = running.exercises[0].sets[0]
        store.send(.edit(.log(exerciseIndex: 0, setID: first.id)))
        await eventually { store.shown?.doneSets == 1 }
        #expect(store.model.header?.connection == Self.line, "logging keeps the line")

        await connection.change(to: .solo)
        await eventually { store.connection == .solo }
        #expect(store.model.header?.connection == nil)
        await connection.end()
        await hear.value
        #expect(store.connection == .solo, "a stream that ends leaves the last state heard")
        pump.cancel()
        follow.cancel()
        await pump.value
        await follow.value
    }

    @Test("A connection whose stream ends at once still gives its state: the line shows, and the store stops listening")
    func store_endedConnection_keepsItsState() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let connection = FakeLiveConnection(.reconnecting)
        let store = scene.store { $0.liveConnection = connection }
        let follow = Task { await store.follow() }
        await eventually { store.shown != nil }
        await store.followConnection()
        #expect(store.connection == .reconnecting)
        #expect(store.model.header?.connection == Self.line)
        follow.cancel()
        await follow.value
    }
}
