import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 20 to 23: what VoiceOver is told about a rest. One phone on the real host (S6's
/// `RestCover`) walked through logs, un-logs, "+30s", "Skip rest", seconds going by, time away, the cover's
/// tasks starting again and the cover reopened; what was said is compared with what the criteria owe,
/// worked out here from the session's workout and the wall clock, in words written here.
@MainActor
@Suite("Workout announcements (adversarial)", .tags(.feature), .timeLimit(.minutes(2)))
struct WorkoutAnnouncementAdversarialTests {
    /// Whole seconds in English words, as criterion 21 writes them ("1 minute, 30 seconds"): not the
    /// formatter under test.
    nonisolated static func words(_ seconds: Int) -> String {
        let (minutes, rest) = (seconds / 60, seconds % 60)
        var parts: [String] = []
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if rest > 0 || minutes == 0 {
            parts.append(rest == 1 ? "1 second" : "\(rest) seconds")
        }
        return parts.joined(separator: ", ")
    }

    /// What criterion 21 owes for `rest` first shown at `now`: nothing for a rest with no time left.
    nonisolated static func owed(for rest: RestTimer?, at now: Date) -> String? {
        guard let rest, rest.remaining(at: now) > .zero else {
            return nil
        }
        let seconds = Int((rest.remaining(at: now) / .seconds(1)).rounded(.up))
        return "Rest, \(words(seconds)) remaining"
    }

    static func recorder(of cover: RestCover) -> FakeAnnouncements? {
        cover.store.announcements as? FakeAnnouncements
    }

    /// What a walk heard, and what it was owed.
    struct Heard {
        var said: [String] = []
        var owed: [String] = []
        var felt: [Haptic] = []
        var trail: [String] = []
        var reopened = 0
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func walk(seed: UInt64, steps: Int = 36) async throws -> Heard {
        let cover = try await RestCover(Fixtures.seedSession())
        var generator = SplitMix64(seed: seed ^ 0xA22)
        var recorders = try [#require(recorder(of: cover))]
        var heard = Heard()
        for _ in 0 ..< steps {
            // No two taps are made at one instant: a rest is told from the one before by when it ends.
            await cover.run(Double(Int.random(in: 1 ... 12, using: &generator)) / 4)
            guard let state = await cover.truth() else {
                break
            }
            let before = state.shownRest
            var isReopened = false
            let cursor = state.checkedCursor
            let done = state.exercises.enumerated().flatMap { index, exercise in
                exercise.sets.filter(\.isDone).map { (index, $0.id) }
            }
            switch Int.random(in: 0 ..< 18, using: &generator) {
            case 0 ..< 5:
                guard let cursor else {
                    continue
                }
                let set = state.exercises[cursor.exerciseIndex].sets[cursor.setIndex].id
                await cover.tap(.log(exerciseIndex: cursor.exerciseIndex, setID: set))
                heard.trail.append("log")
            case 5:
                guard let (exercise, set) = done.last else {
                    continue
                }
                await cover.tap(.unlog(exerciseIndex: exercise, setID: set))
                heard.trail.append("unlog")
            case 6 ..< 8:
                await cover.tap(.extendRest)
                heard.trail.append("+30s")
            case 8:
                await cover.tap(.skipRest)
                heard.trail.append("skip")
            case 9:
                guard let cursor else {
                    continue
                }
                let set = state.exercises[cursor.exerciseIndex].sets[cursor.setIndex].id
                await cover.tap(.stepReps(exerciseIndex: cursor.exerciseIndex, setID: set, .increment))
                heard.trail.append("step")
            case 10 ..< 13:
                let seconds = Int.random(in: 1 ... 100, using: &generator)
                await cover.run(Double(seconds))
                heard.trail.append("run\(seconds)")
            case 13:
                let seconds = Double.random(in: 1 ... 400, using: &generator)
                await cover.suspend(seconds)
                heard.trail.append("away")
            case 14:
                // A redraw: everything a view reads, read again.
                _ = (cover.store.model, cover.store.restPanel, cover.store.finishSheet, cover.store.shownRest)
                heard.trail.append("redraw")
            case 15, 16:
                await cover.restartTasks()
                heard.trail.append("restart")
            default:
                await cover.reopen()
                try recorders.append(#require(recorder(of: cover)))
                isReopened = true
                heard.reopened += 1
                heard.trail.append("reopen")
            }
            let after = await cover.truth()?.shownRest
            if isReopened || after != before, let text = owed(for: after, at: cover.now) {
                heard.owed.append(text)
            }
        }
        heard.felt = await cover.played()
        for recorder in recorders {
            heard.said += await recorder.announced
        }
        await cover.close()
        return heard
    }
}

extension WorkoutAnnouncementAdversarialTests {
    @Test(
        "A walk of a workout: each new rest is said once with its time in words, and Rest over where it is felt",
        arguments: RestSeeds.all
    )
    func walk_saysEachRestOnce(seed: UInt64) async throws {
        let heard = try await Self.walk(seed: seed)
        let starts = heard.said.filter { $0 != "Rest over" }
        #expect(starts == heard.owed, "seed \(seed): \(heard.trail.joined(separator: " "))")
        let over = heard.said.count { $0 == "Rest over" }
        #expect(over == heard.felt.count { $0 == .restOver }, "seed \(seed): \(heard.trail.joined(separator: " "))")
        #expect(heard.said.allSatisfy { !$0.contains(":") }, "a time as digits and a colon was announced")
    }

    @Test("The walk is not vacuous: rests begin, are extended, end on time, and covers reopen on running rests")
    func walk_isNotVacuous() async throws {
        var (starts, over, reopened, seconds) = (0, 0, 0, 0)
        for seed in RestSeeds.all.prefix(40) {
            let heard = try await Self.walk(seed: seed)
            starts += heard.owed.count
            over += heard.said.count { $0 == "Rest over" }
            reopened += heard.reopened
            seconds += heard.owed.count { $0.hasSuffix("seconds remaining") && !$0.contains("minute") }
        }
        print("announcement walk, first 40 seeds: rests said \(starts), under a minute \(seconds),"
            + " Rest over \(over), covers reopened \(reopened)")
        #expect(starts >= 200)
        #expect(seconds >= 20)
        #expect(over >= 20)
        #expect(reopened >= 40)
    }

    @Test("Rest over is said after it is felt, once: a haptic that is slow holds the words back")
    func restOver_isSaidAfterItIsFelt() async throws {
        let running = try Fixtures.seedSession()
        let (haptics, said, clock) = (GatedHaptics(), FakeAnnouncements(), RestProbeClock())
        let store = try WorkoutScene.onFake(live: running).store {
            $0.haptics = haptics
            $0.announcements = said
            $0.continuousClock = clock
            $0.date = DateGenerator { Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1)) }
        }
        let following = Task { await store.follow() }
        await eventually("the session's first update") { store.shown != nil }
        store.send(.edit(.log(exerciseIndex: 0, setID: running.exercises[0].sets[0].id)))
        await store.drain()
        await eventually("the rest to be shown") { store.shownRest != nil }
        let keeper = Task { await store.keepRestTime() }
        await eventually("the rest's task to sleep") { clock.sleeps.value > 0 }
        #expect(await said.announced == ["Rest, 2 minutes, 30 seconds remaining"])
        await haptics.hold()
        let length = Int(running.exercises[0].rest.duration / .seconds(1))
        for _ in 0 ..< length {
            let sleeps = clock.sleeps.value
            await clock.base.advance(by: .seconds(1))
            await eventually("a second of the rest") { clock.sleeps.value > sleeps || store.restPanel?.isOver == true }
        }
        var turns = 0
        while await !haptics.played.contains(.restOver), turns < 20000 {
            turns += 1
            await Task.yield()
        }
        await giveWay()
        #expect(await haptics.played.suffix(1) == [.restOver])
        #expect(await said.announced.count == 1, "the words came before the haptic had been played")
        await haptics.release()
        await SaveCover.ended([keeper], "the rest's task")
        #expect(await said.announced == ["Rest, 2 minutes, 30 seconds remaining", "Rest over"])
        // A second task on the same, ended, rest says nothing more.
        await store.keepRestTime()
        #expect(await said.announced.count == 2)
        following.cancel()
    }

    @Test("The time is said by the whole second, rounded up, in words and with the singular forms", arguments: [
        (150.0, "Rest, 2 minutes, 30 seconds remaining"), (149.2, "Rest, 2 minutes, 30 seconds remaining"),
        (120.0, "Rest, 2 minutes remaining"), (61.0, "Rest, 1 minute, 1 second remaining"),
        (60.0, "Rest, 1 minute remaining"), (59.01, "Rest, 1 minute remaining"), (45.0, "Rest, 45 seconds remaining"),
        (1.0, "Rest, 1 second remaining"), (0.2, "Rest, 1 second remaining"), (600.0, "Rest, 10 minutes remaining")
    ])
    func announcement_isInWords(left: TimeInterval, wanted: String) {
        let rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(left), total: .seconds(600))
        for locale in [Fixtures.locale, Locale(identifier: "en_GB"), Locale(identifier: "en_DE")] {
            #expect(WorkoutPresentation.restAnnouncement(rest, at: Fixtures.now, locale: locale) == wanted)
        }
        #expect(Self.owed(for: rest, at: Fixtures.now) == wanted, "the walk's own words are the criterion's")
    }

    @Test("A rest with no time left is not announced, and nothing is said in digits")
    func announcement_noneAtZero() {
        let rest = RestTimer(endsAt: Fixtures.now, total: .seconds(90))
        #expect(WorkoutPresentation.restAnnouncement(rest, at: Fixtures.now, locale: Fixtures.locale) == nil)
        #expect(WorkoutPresentation.restAnnouncement(rest, at: Fixtures.now + 0.001, locale: Fixtures.locale) == nil)
        #expect(WorkoutPresentation.restAnnouncement(rest, at: Fixtures.now - 0.001, locale: Fixtures.locale)
            == "Rest, 1 second remaining")
        #expect(WorkoutCopy.restOver == "Rest over")
    }
}
