import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S2: `FakeCompanionNetwork` and `FakeCompanionTransport`, what CI exercises in place of WatchConnectivity's
/// queued calls (criterion 11): delivery both ways, the latest context alone after a disconnect, records in order,
/// the codec's refusals, and a missing watch app (criterion 12).
@Suite("FakeCompanionTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeCompanionTransportTests {
    @Test("While connected, a context and a file reach the watch and a record the phone before the call returns")
    func payloads_goBothWays() async throws {
        let network = FakeCompanionNetwork()
        let program = try Fixtures.seedProgram()
        let file = CompanionFile.program(program, customExercises: [], lastPerformance: [:])
        try await network.phone.updateContext(Self.context(1))
        try await network.phone.transfer(file)
        try await network.watch.enqueue(Self.record(1))
        #expect(await FakeLiveWorkoutTransportTests.next(1, of: network.watch.receivedContext).map(\.revision) == [1])
        let files = await FakeLiveWorkoutTransportTests.next(1, of: network.watch.receivedFiles)
        let sameFile = files == [file]
        #expect(sameFile, "the program file did not arrive as sent")
        #expect(await FakeLiveWorkoutTransportTests.next(1, of: network.phone.receivedRecords)
            .map(\.workoutID) == [Self.workout(1)])
        #expect(network.phone.sentContexts.map(\.revision) == [1] && network.phone.sentFiles.count == 1)
        #expect(network.watch.sentRecords.map(\.workoutID) == [Self.workout(1)])
        #expect(network.phone.sentRecords.isEmpty && network.watch.sentContexts.isEmpty)
        #expect(await network.phone.isPaired && network.phone.isWatchAppInstalled && network.isConnected)
        #expect(await network.watch.isPaired && network.watch.isWatchAppInstalled)
    }

    @Test("After a disconnect, the latest context arrives alone, and every record and file in the order sent")
    func disconnect_latestContextAlone_recordsInOrder() async throws {
        let network = FakeCompanionNetwork()
        network.disconnect()
        #expect(!network.isConnected)
        for revision in UInt64(1) ... 3 {
            try await network.phone.updateContext(Self.context(revision))
        }
        for number in 1 ... 3 {
            try await network.watch.enqueue(Self.record(number))
        }
        try await network.watch.transfer(.workoutLog(Self.record(4)))
        #expect(network.phone.sentContexts.map(\.revision) == [1, 2, 3])
        network.connect()
        try await network.phone.updateContext(Self.context(4))
        #expect(await FakeLiveWorkoutTransportTests.next(2, of: network.watch.receivedContext).map(\.revision) == [
            3,
            4
        ])
        let records = await FakeLiveWorkoutTransportTests.next(3, of: network.phone.receivedRecords).map(\.workoutID)
        #expect(records == [1, 2, 3].map(Self.workout))
        let files = await FakeLiveWorkoutTransportTests.next(1, of: network.phone.receivedFiles)
        #expect(files.map(Self.workoutID) == [Self.workout(4)])
        network.disconnect()
        network.connect() // nothing waits, nothing arrives twice
        try await network.watch.enqueue(Self.record(5))
        #expect(await FakeLiveWorkoutTransportTests.next(1, of: network.phone.receivedRecords)
            .map(\.workoutID) == [Self.workout(5)])
    }

    @Test("A record over 60 000 bytes is refused as user info, sending nothing, and arrives whole as a file")
    func enqueue_refusesALargeRecord_fileCarriesIt() async throws {
        let network = FakeCompanionNetwork()
        var large = Self.record(1)
        large.log = (1 ... 600).map { seq in
            EventBuilders.envelope(.restSkipped, device: EventBuilders.watch, seq: UInt64(seq), at: EventBuilders.start)
        }
        #expect(try CompanionCodec.delivery(for: large) == .file)
        await #expect(throws: CompanionCodecError.tooLarge) {
            try await network.watch.enqueue(large)
        }
        #expect(network.watch.sentRecords.isEmpty)
        try await network.watch.transfer(.workoutLog(large))
        let files = await FakeLiveWorkoutTransportTests.next(1, of: network.phone.receivedFiles)
        let same = files == [.workoutLog(large)]
        #expect(same, "the large record did not arrive whole")
    }

    @Test("A context over the limit is refused and sends nothing")
    func updateContext_refusesALargeContext() async throws {
        let network = FakeCompanionNetwork()
        var context = Self.context(1)
        context.programName = String(repeating: "x", count: CompanionCodec.contextLimit)
        await #expect(throws: CompanionCodecError.tooLarge) {
            try await network.phone.updateContext(context)
        }
        #expect(network.phone.sentContexts.isEmpty)
    }

    @Test("Without the watch app every send throws unavailable and records nothing; installing it sends again")
    func watchAppNotInstalled_refusesEverySend() async throws {
        let network = FakeCompanionNetwork(isWatchAppInstalled: false)
        #expect(await !network.phone.isWatchAppInstalled && network.phone.isPaired)
        try await Self.expectUnavailable(network.phone)
        network.setWatchAppInstalled(true)
        try await network.phone.updateContext(Self.context(2))
        #expect(await FakeLiveWorkoutTransportTests.next(1, of: network.watch.receivedContext).map(\.revision) == [2])
        network.setWatchAppInstalled(false)
        try await Self.expectUnavailable(network.watch)
    }

    @Test("A transport made alone is unpaired, and every send throws unavailable")
    func alone_reachesNoOne() async throws {
        let alone = FakeCompanionTransport()
        #expect(await !alone.isPaired && !alone.isWatchAppInstalled)
        try await Self.expectUnavailable(alone)
    }
}

extension FakeCompanionTransportTests {
    static func workout(_ number: Int) -> WorkoutID {
        WorkoutID(EventBuilders.uuid(0xC000 + number))
    }

    static func context(_ revision: UInt64) -> CompanionContext {
        CompanionContext(
            revision: revision, programID: nil, programName: nil, weekIndex: 0, weekCount: 0, isDeload: false,
            nextDay: nil, settings: WatchSettings(.default), acknowledgedWorkoutIDs: [workout(1)]
        )
    }

    /// Workout `number`'s record, with an empty log.
    static func record(_ number: Int) -> FinishedWorkoutRecord {
        FinishedWorkoutRecord(
            workoutID: workout(number), log: [], healthKitUUID: nil, finishedAt: EventBuilders.start,
            device: EventBuilders.watch
        )
    }

    /// The workout a `.workoutLog` file carries; nil for a program file.
    static func workoutID(_ file: CompanionFile) -> WorkoutID? {
        guard case let .workoutLog(record) = file else {
            return nil
        }
        return record.workoutID
    }

    /// Each of `transport`'s three sends throws `unavailable`, and it records none of them.
    static func expectUnavailable(
        _ transport: FakeCompanionTransport,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        await #expect(throws: CompanionTransportError.unavailable, sourceLocation: sourceLocation) {
            try await transport.updateContext(context(9))
        }
        await #expect(throws: CompanionTransportError.unavailable, sourceLocation: sourceLocation) {
            try await transport.transfer(.workoutLog(record(9)))
        }
        await #expect(throws: CompanionTransportError.unavailable, sourceLocation: sourceLocation) {
            try await transport.enqueue(record(9))
        }
        let recorded = transport.sentContexts.count + transport.sentFiles.count + transport.sentRecords.count
        #expect(recorded == 0, sourceLocation: sourceLocation)
    }
}
