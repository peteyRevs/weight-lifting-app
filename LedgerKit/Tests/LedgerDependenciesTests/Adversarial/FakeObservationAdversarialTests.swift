import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: the fakes' `observe…()` streams (ADR-008 decision 4: shared state behind a `Mutex`,
/// each stream yielding under the lock). The first value is there before the call returns, only a change is
/// emitted, a refused write emits nothing, every subscriber sees every change in write order, writers racing
/// from many tasks lose nothing, a consumer that writes back does not deadlock, and an ended stream stops
/// nothing else.
@Suite("Adversarial F07 S1 · fake observation", .timeLimit(.minutes(1)))
struct FakeObservationAdversarialTests {
    static func settings(_ seconds: Int) -> Settings {
        var settings = Settings.default
        settings.defaultRest = RestDuration(seconds: seconds) ?? .defaultRest
        return settings
    }

    static func exercise(_ number: Int) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(0xAD0000 + number)),
            name: "Lift \(number)",
            shortName: "L\(number)",
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [],
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(45)],
            isCustom: true,
            curatedAlternatives: []
        )
    }

    @Test("The current value is the stream's first, even when a write follows the call at once")
    func firstValue_isTheStateWhenObserved() async throws {
        let repository = InMemorySettingsRepository()
        let stream = repository.observe()
        var values = stream.makeAsyncIterator() // S1 fix round 1 (sanctioned): read after each write
        #expect(await values.next() == .default)
        try await repository.save(Self.settings(120))
        #expect(await values.next() == Self.settings(120))
    }

    @Test("Saves that change nothing emit nothing: the stream is the distinct values in order")
    func unchangedWrites_emitNothing() async throws {
        let repository = InMemorySettingsRepository()
        var values = repository.observe().makeAsyncIterator() // S1 fix round 1 (sanctioned): read after each change
        var seen: [Int] = await values.next().map { [$0.defaultRest.seconds] } ?? []
        // An unchanged save emits nothing: the value after it is the next real change, never a repeat.
        for seconds in [90, 120, 120, 90, 90, 150] {
            try await repository.save(Self.settings(seconds))
            if seconds != seen.last, let value = await values.next() {
                seen.append(value.defaultRest.seconds)
            }
        }
        #expect(seen == [90, 120, 90, 150])
    }

    @Test("A refused save emits nothing; the next save is the second value")
    func refusedWrite_emitsNothing() async throws {
        let repository = InMemoryProgramRepository()
        let stream = repository.observeActive()
        let program = try Fixtures.seedProgram()
        var broken = program
        broken.days[0].slots[1] = broken.days[0].slots[0]
        var values = stream.makeAsyncIterator() // S1 fix round 1 (sanctioned): read after each write
        #expect(await values.next() == .some(nil))
        await #expect(throws: RepositoryError.self) { try await repository.save(broken) }
        try await repository.save(program) // the refused save emitted nothing: the next value is this one
        #expect(await values.next() == program)
    }

    @Test("Fifty subscribers each see every change, in write order")
    func manySubscribers_seeEveryChange() async throws {
        let repository = InMemoryExerciseRepository()
        // S1 fix round 1 (sanctioned): every subscriber reads after each write.
        var iterators = (0 ..< 50).map { _ in repository.observeAll().makeAsyncIterator() }
        var counts = Array(repeating: [Int](), count: iterators.count)
        for number in -1 ..< 5 {
            if number >= 0 {
                try await repository.save(Self.exercise(number))
            }
            for index in iterators.indices {
                await counts[index].append(iterators[index].next()?.count ?? -1)
            }
        }
        for seen in counts {
            #expect(seen == [0, 1, 2, 3, 4, 5])
        }
    }

    /// S1 fix round 1 (sanctioned): a stream keeps only its newest value, as GRDB's does, so it promises the final
    /// state and order, not every state in between.
    @Test(
        "Five hundred saves racing from as many tasks: none is lost, and the stream ends on the final state, in order"
    )
    func racingWriters_endOnTheFinalState_inOrder() async throws {
        let repository = InMemoryExerciseRepository()
        let stream = repository.observeAll()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 0 ..< 500 {
                group.addTask { try await repository.save(Self.exercise(number)) }
            }
            try await group.waitForAll()
        }
        #expect(try await repository.all().count == 500)
        var counts: [Int] = []
        for await value in stream {
            counts.append(value.count)
            if value.count == 500 {
                break
            }
        }
        #expect(counts.last == 500)
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 }, "\(counts)")
    }
}

extension FakeObservationAdversarialTests {
    @Test("Workouts materialised from many tasks at once: the records equal those of the same history stored in turn")
    func racingMaterialisations_keepRecordsAFunctionOfHistory() async throws {
        let history = try Fixtures.history(weeks: 8)
        let racing = InMemoryStores()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for workout in history.shuffled() {
                group.addTask { try await racing.workouts.materialize(workout, slotUpdates: []) }
            }
            try await group.waitForAll()
        }
        let inTurn = InMemoryStores(seed: InMemoryStores.Seed(workouts: history))
        for exercise in try Fixtures.seedProgram().days.flatMap(\.slots).map(\.exerciseID) {
            #expect(try await racing.stats.personalRecords(exerciseID: exercise)
                == inTurn.stats.personalRecords(exerciseID: exercise))
        }
    }

    @Test("A consumer that saves when it sees a value does not deadlock the store")
    func consumerWritingBack_doesNotDeadlock() async throws {
        let repository = InMemorySettingsRepository()
        let stream = repository.observe()
        // S1 fix round 1 (sanctioned): the consumer says when it has read its first value, and only then is 120
        // saved, since a stream keeps only its newest value.
        let (started, ready) = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var seen: [Int] = []
            for await value in stream {
                seen.append(value.defaultRest.seconds)
                ready.yield()
                if value.defaultRest.seconds == 120 {
                    try await repository.save(Self.settings(150))
                }
                if value.defaultRest.seconds == 150 {
                    break
                }
            }
            return seen
        }
        var signals = started.makeAsyncIterator()
        await signals.next()
        try await repository.save(Self.settings(120))
        #expect(try await consumer.value == [90, 120, 150])
    }

    @Test("A cancelled consumer's stream ends; later writes and other streams carry on")
    func cancelledConsumer_endsOnlyItsStream() async throws {
        let repository = InMemorySettingsRepository()
        let other = repository.observe()
        let consumer = Task {
            var count = 0
            for await _ in repository.observe() {
                count += 1
            }
            return count
        }
        consumer.cancel()
        _ = await consumer.value
        for _ in 0 ..< 100 {
            _ = repository.observe() // dropped at once, never iterated
        }
        var values = other.makeAsyncIterator() // S1 fix round 1 (sanctioned): read after each write
        #expect(await values.next() == .default)
        try await repository.save(Self.settings(120))
        #expect(await values.next() == Self.settings(120))
    }

    @Test("A materialised workout's slot updates reach observeActive, as the database's observation of slot_miss does")
    func slotUpdates_emitTheActiveProgram() async throws {
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(programs: [Fixtures.seedProgram()]))
        let stream = stores.programs.observeActive()
        let workout = try #require(Fixtures.history(weeks: 1).last)
        var slot = try #require(try await stores.programs.active()?.days[0].slots[0])
        slot.misses = [3]
        var values = stream.makeAsyncIterator() // S1 fix round 1 (sanctioned): the first value before the write
        _ = await values.next()
        try await stores.workouts.materialize(workout, slotUpdates: [slot])
        #expect(await values.next()??.days[0].slots[0].misses == [3])
    }

    @Test("The event store keeps every envelope appended from a hundred tasks at once")
    func racingAppends_keepEveryEnvelope() async throws {
        let store = InMemoryWorkoutEventStore()
        let envelopes = (1 ... 100).map { seq in
            EventBuilders.envelope(.restSkipped, seq: UInt64(seq), at: EventBuilders.start)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for envelope in envelopes {
                group.addTask { _ = try await store.append([envelope]) }
            }
            try await group.waitForAll()
        }
        #expect(try await Set(store.envelopes(for: EventBuilders.workoutID)) == Set(envelopes))
        let highest = await store.highestSeq(for: EventBuilders.workoutID, device: EventBuilders.phone)
        #expect(highest == 100)
    }
}

/// F07 S1 adversarial round 1: `withTestDependencies` and `inMemoryStores(seed:)` as a store test meets them.
@Suite("Adversarial F07 S1 · test dependencies", .timeLimit(.minutes(1)))
struct TestDependenciesAdversarialTests {
    @Test("Nineteen tests running at once each see only their own stores")
    func parallelTests_doNotShareStores() async throws {
        try await withThrowingTaskGroup(of: Int.self) { group in
            for seconds in stride(from: 30, through: 300, by: 15) {
                group.addTask {
                    try await withTestDependencies {
                        $0.inMemoryStores()
                    } operation: {
                        @Dependency(\.settingsRepository) var settings
                        var saved = Settings.default
                        saved.defaultRest = RestDuration(seconds: seconds) ?? .defaultRest
                        try await settings.save(saved)
                        await Task.yield()
                        return try await settings.load().defaultRest.seconds == seconds ? 0 : 1
                    }
                }
            }
            let leaks = try await group.reduce(0, +)
            #expect(leaks == 0)
        }
    }

    @Test("Each withTestDependencies starts its ids again at 0")
    func uuids_startAgainInEveryRun() {
        for _ in 0 ..< 2 {
            withTestDependencies {
                @Dependency(\.uuid) var uuid
                #expect(uuid() == UUID(0))
            }
        }
    }

    @Test("F7-6: the stats of inMemoryStores read the date the test set, even when set after binding them")
    func statsDate_isTheDateWhenBound() async throws {
        let later = Fixtures.now.addingTimeInterval(14 * 86400)
        let workout = try #require(Fixtures.history(weeks: 1).last)
        try await withTestDependencies {
            $0.inMemoryStores()
            $0.date = .constant(later)
        } operation: {
            @Dependency(\.workoutRepository) var workouts
            @Dependency(\.statsQueries) var stats
            @Dependency(\.date.now) var now
            try await workouts.materialize(workout, slotUpdates: [])
            let calendar = try WeekCalendar(
                startDate: Fixtures.seedProgram().startDate,
                weekStart: .monday,
                calendar: Fixtures.calendar
            )
            // One week back from `now` (two weeks after the workout) holds nothing; from `Fixtures.now`, it does.
            let byWeek = try await stats.e1RMByWeek(
                exerciseID: Fixtures.CatalogID.benchPress,
                lastWeeks: 1,
                calendar: calendar
            )
            #expect(now == later)
            #expect(byWeek.isEmpty, "the stats still read Fixtures.now, not the date the test set")
        }
    }
}
