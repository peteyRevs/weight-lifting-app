import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S5: the revision the phone sends a context under, the records it acknowledges, and the program file with its
/// canonical bytes, which the phone tells apart by their SHA-256.
@Suite("CompanionContextBuilder: revision, acknowledgements, file", .tags(.domain))
struct CompanionContextBuilderFileTests {
    typealias Seed = LedgerFakes.Fixtures

    // MARK: Revision

    @Test("The revision is above the stored one and at least the clock's milliseconds, whichever is higher")
    func revision_isTheHigherOfStoredPlusOneAndTheClock() {
        let now = Date(timeIntervalSince1970: 1_789_536_000.123_9)
        let clock: UInt64 = 1_789_536_000_123
        #expect(CompanionContextBuilder.revision(after: nil, now: now) == clock)
        #expect(CompanionContextBuilder.revision(after: clock - 50, now: now) == clock)
        #expect(CompanionContextBuilder.revision(after: clock, now: now) == clock + 1)
        #expect(CompanionContextBuilder.revision(after: clock + 9000, now: now) == clock + 9001)
    }

    @Test("A clock before 1970 or not a number counts for nothing, and the largest revision does not wrap")
    func revision_edges() {
        #expect(CompanionContextBuilder.revision(after: nil, now: Date(timeIntervalSince1970: -5)) == 1)
        #expect(CompanionContextBuilder.revision(after: 41, now: Date(timeIntervalSince1970: .nan)) == 42)
        #expect(CompanionContextBuilder.revision(after: 41, now: .distantFuture) > 41)
        #expect(CompanionContextBuilder.revision(after: .max, now: .now) == .max)
        #expect(CompanionContextBuilder.revision(after: 3, now: Date(timeIntervalSince1970: 1e300)) == 4)
    }

    // MARK: Acknowledgements

    @Test("The watch's stored records are acknowledged newest first, the phone's own archives never, 64 at most")
    func acknowledged_watchRecordsNewestFirst() throws {
        let watch = (0 ..< 70).map { CompanionContextBuilderTests.log(
            $0,
            device: EventBuilders.watch,
            created: Double($0)
        ) }
        let own = CompanionContextBuilderTests.log(100, device: EventBuilders.phone, created: 1000)
        let logs = Array(watch.prefix(35)) + [own] + watch.dropFirst(35)
        let context = try CompanionContextBuilderTests.context(at: Seed.now, storedLogs: logs)
        let expected = (6 ..< 70).reversed().map(CompanionContextBuilderTests.workoutID)
        #expect(context.acknowledgedWorkoutIDs.count == CompanionContextBuilder.acknowledgedWindow)
        let newestFirst = context.acknowledgedWorkoutIDs == expected
        #expect(newestFirst, "not the newest 64 of the watch's records, newest first")
        let few = try CompanionContextBuilderTests.context(at: Seed.now, storedLogs: Array(watch.prefix(2)) + [own])
        #expect(few.acknowledgedWorkoutIDs == [1, 0].map(CompanionContextBuilderTests.workoutID))
    }

    // MARK: The program file

    @Test("The file carries the custom exercises the slots name, in id order, and the last lines of their exercises")
    func programFile_customExercisesAndLastPerformance() throws {
        var program = try Seed.seedProgram()
        program.days[0].slots[1].exerciseID = Self.custom(2).id
        program.days[3].slots[0].exerciseID = Self.custom(1).id
        var exercises = try CompanionContextBuilderTests.exercises()
        for number in 1 ... 3 {
            exercises[Self.custom(number).id] = Self.custom(number)
        }
        let squat = Seed.CatalogID.backSquat
        let lines = [squat: Self.line(5), Self.custom(1).id: Self.line(3), Self.custom(3).id: Self.line(4)]
        let file = CompanionContextBuilder.programFile(program, exercises: exercises, lastPerformance: lines)
        guard case let .program(sent, custom, performance) = file else {
            Issue.record("no program file")
            return
        }
        let sameProgram = sent == program
        #expect(sameProgram, "the file does not carry the program")
        #expect(custom.map(\.id) == [Self.custom(1).id, Self.custom(2).id])
        #expect(performance == [squat: Self.line(5), Self.custom(1).id: Self.line(3)])
        #expect(CompanionContextBuilder.programFile(nil, exercises: exercises, lastPerformance: lines) == nil)
    }

    @Test("Equal files encode to the same bytes, however their sets and dictionaries were built, and decode equal")
    func programFile_bytesAreCanonical() throws {
        var program = try Seed.seedProgram()
        var reversed = program
        program.days[0].slots[0].misses = Set(0 ..< 12)
        var misses = Set<Int>(minimumCapacity: 512)
        for week in (0 ..< 12).reversed() {
            misses.insert(week)
        }
        reversed.days[0].slots[0].misses = misses
        let ids = (1 ... 40).map { ExerciseID(EventBuilders.uuid(0xE000 + $0)) }
        var forward: [ExerciseID: LastPerformance] = [:]
        var backward = [ExerciseID: LastPerformance](minimumCapacity: 512)
        for (index, id) in ids.enumerated() {
            forward[id] = Self.line(index + 1)
        }
        for (index, id) in ids.enumerated().reversed() {
            backward[id] = Self.line(index + 1)
        }
        let first = CompanionFile.program(program, customExercises: [], lastPerformance: forward)
        let second = CompanionFile.program(reversed, customExercises: [], lastPerformance: backward)
        let bytes = try CompanionCodec.encode(first)
        let canonical = try bytes == CompanionCodec.encode(second)
        #expect(canonical, "equal files encoded to different bytes")
        let same = try CompanionCodec.decode(CompanionFile.self, from: bytes) == first
        #expect(same, "the canonical bytes did not decode to the file")
        let record = FinishedWorkoutRecord(
            workoutID: EventBuilders.workoutID,
            log: [],
            healthKitUUID: nil,
            finishedAt: EventBuilders.start,
            device: EventBuilders.watch
        )
        let log = CompanionFile.workoutLog(record)
        #expect(try CompanionCodec.decode(CompanionFile.self, from: CompanionCodec.encode(log)) == log)
    }
}

extension CompanionContextBuilderFileTests {
    /// Custom exercise `number`.
    static func custom(_ number: Int) -> Exercise {
        Exercise(
            id: ExerciseID(EventBuilders.uuid(0xC000 + number)),
            name: "Custom \(number)",
            shortName: "C\(number)",
            equipment: .machine,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(50)],
            isCustom: true
        )
    }

    /// A "Last" line of `reps` reps.
    static func line(_ reps: Int) -> LastPerformance {
        LastPerformance(date: EventBuilders.start, sets: 3, reps: reps, load: .pounds(100))
    }
}
