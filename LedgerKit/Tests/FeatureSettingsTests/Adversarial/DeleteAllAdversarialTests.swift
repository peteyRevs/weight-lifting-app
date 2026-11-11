@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S3 G2 (adversarial): "Delete all data"'s store and its typed word, attacked where the implementer's tables stop:
/// look-alike and invisible characters, other locales, a session that cannot say whether a workout is live, steps sent
/// out of order, and a double tap in one turn.
@MainActor
@Suite("Adversarial F14 S3 · Delete all data, the store", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct DeleteAllAdversarialTests {
    // MARK: The typed word

    @Test(
        "Criterion 6.2 (G2). Look-alikes, a word inside other text, and a word split by a space never match",
        arguments: [
            "DЕLЕTЕ", // Cyrillic Е (U+0415)
            "DELETΕ", // Greek Epsilon (U+0395)
            "DELE TE",
            "DELETE DELETE",
            "UNDELETE",
            "DELETE.",
            "\"DELETE\"",
            "DELETE\u{0301}" // a combining acute accent on the last E
        ]
    )
    func lookAlikes_neverMatch(_ text: String) {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "tr_TR"), Locale(identifier: "de_DE")] {
            #expect(
                !DeleteAllPresentation.matches(text, locale: locale),
                "\(text.unicodeScalars.map(\.value)) in \(locale.identifier)"
            )
        }
    }

    @Test(
        "Criterion 6.2 (G2). The word pasted with the blanks a paste brings matches, in any locale's case folding",
        arguments: ["DELETE\n", "\tdelete", "\u{00A0}DELETE\u{00A0}", "\u{2003}Delete\r\n", "dElEtE"]
    )
    func pastedWord_matches(_ text: String) {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "tr_TR"), Locale(identifier: "ar_SA")] {
            #expect(
                DeleteAllPresentation.matches(text, locale: locale),
                "\(text.debugDescription) in \(locale.identifier)"
            )
        }
    }

    // MARK: Steps out of order

    @Test("G2. The word typed and Delete everything tapped while the warning is up erase nothing and skip no step")
    func warningStep_ignoresTheWordAndTheConfirm() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.confirmDeleteAll)
        scene.store.send(.continueDeleteAll)
        #expect(scene.store.deleteAll == nil, "Continue with no warning up opened nothing")
        scene.store.send(.deleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        #expect(scene.store.deleteAll?.step == .warning && scene.store.deleteAll?.text == "")
        scene.store.send(.continueDeleteAll)
        scene.store.send(.deleteAll) // the row again, behind the sheet: the draft stays
        #expect(try scene.model.deleteSheet?.confirm == nil, "the sheet opens with nothing typed")
        await Task.yield()
        #expect(reset.calls.isEmpty)
    }

    @Test("N23 (G2). Two taps on Delete everything in one turn erase once; nothing after the erase erases again")
    func doubleTapInOneTurn_erasesOnce() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll == nil }
        scene.store.send(.confirmDeleteAll)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(reset.calls.count == 1)
    }

    // MARK: A session that cannot answer

    @Test("N19 (G2). When the session cannot say whether a workout is live, nothing is erased and the sheet says so")
    func unreadableSession_erasesNothing() async throws {
        var held: HeldReset?
        let scene = try SettingsScene(seed: DeleteAllScene.history(), session: UnreadableSession()) { stores in
            let made = HeldReset(stores.reset)
            held = made
            return made
        }
        let reset = try #require(held)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll?.isErasing == false }
        #expect(scene.store.deleteAll?.failed == true)
        #expect(reset.calls.isEmpty)
        #expect(try await !scene.memory.workouts.recent(limit: 100).isEmpty)
    }
}

/// A session whose `updates()` says nothing is live and whose `current()` throws: the host could not read its log.
private actor UnreadableSession: WorkoutSessionClient {
    struct Unreadable: Error {}

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        AsyncStream { $0.yield(WorkoutSessionUpdate(state: nil)) }
    }

    func current() throws -> WorkoutState? {
        throw Unreadable()
    }

    func start(_: WorkoutState) throws {
        throw Unreadable()
    }

    func apply(_: WorkoutEvent) throws -> WorkoutState {
        throw Unreadable()
    }

    func finish(endedAt _: Date) throws -> WorkoutState {
        throw Unreadable()
    }

    func discard(endedAt _: Date) throws {
        throw Unreadable()
    }
}
