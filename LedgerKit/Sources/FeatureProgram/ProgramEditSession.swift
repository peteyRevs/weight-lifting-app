import Dependencies
import LedgerDependencies
import LedgerDomain
import Observation

/// An edit a session queues and stores: complete with its ids, and exactly one editing call on the program it
/// is applied to. The builder's edits and the Day editor's conform; only the builder's can throw.
nonisolated protocol ProgramEdit: Hashable, Sendable {
    func applied(to program: Program) throws -> Program
}

nonisolated extension ProgramBuilderEdit: ProgramEdit {}

nonisolated extension DayEditorEdit: ProgramEdit {}

/// One program being edited (F11 S13, criteria 1 to 6): the program as last stored, the edits not stored yet,
/// in order, and the one loop that stores them through `ProgramRepository.update`.
///
/// **What is shown** is the stored program with the waiting edits applied in order, worked out again whenever
/// either changes, so an edit is on screen before `enqueue` returns. An edit that would change nothing on
/// screen is not queued, and so never written (a stepper at its limit, a rename to the stored name).
///
/// **One loop.** `run(prepare:finished:)`, from the root's task, writes while edits wait: it takes every
/// waiting edit, calls `update` once with all of them, and goes round again for those queued meanwhile. So
/// the first edit is written at once and edits made during a write go together in the next one. The change
/// it hands `update` captures the edits and nothing else, and applies them to the program `update` reads,
/// never to a copy kept here: a workout's save made meanwhile (misses, a swap) is kept.
///
/// **Each edit reaches the stored program once.** When `update` returns, the program it returns is adopted
/// and exactly the edits sent are dropped, in one synchronous step. A program the store emits while a write
/// runs is kept aside, never drawn under edits that may already be in it; the returned program wins. A write
/// that throws `CancellationError` while its task is cancelled stored nothing (F11 S3): its edits stay at the
/// front and the next run sends them. Any other failure stored nothing either, and every waiting edit, sent
/// or not, is dropped: the screen goes back to the stored program, and `finished` says why.
@MainActor @Observable
final class ProgramEditSession<Edit: ProgramEdit> {
    /// How a write ended, for the store to answer.
    enum Outcome {
        /// Every edit sent is stored.
        case stored
        /// Nothing was stored, and the waiting edits are gone.
        case failed(any Error)
    }

    /// The program as last stored: emitted by the store, or returned by `update`. Nil when none is active.
    private(set) var stored: Program?
    /// Whether the store has said which program is active, nil included.
    private(set) var hasHeard = false
    /// The stored program with the waiting edits applied in order: what the screen draws.
    private(set) var shown: Program?
    /// The edits not stored yet, oldest first; those of a write that runs are at the front.
    private(set) var waiting: [Edit] = []
    private(set) var isWriting = false
    /// A program emitted while a write ran, kept aside until it ends.
    private(set) var heardDuringWrite: Program??

    /// Wakes the loop of `run`; the newest run's.
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?

    @ObservationIgnored @Dependency(\.programRepository) private var programs

    /// No edit waits and no write runs.
    var isIdle: Bool {
        waiting.isEmpty && !isWriting
    }

    /// The store's newest word on the active program. While a write runs it is kept aside.
    func hear(_ program: Program?) {
        guard !isWriting else {
            heardDuringWrite = .some(program)
            return
        }
        adopt(program)
    }

    /// Applies `edit` to the program on screen and queues it, unless that changes nothing. Returns whether
    /// it was queued.
    @discardableResult
    func enqueue(_ edit: Edit) -> Bool {
        // An edit the program on screen refuses would change nothing; there is no error to show for it.
        guard let shown, let next = try? edit.applied(to: shown), next != shown else {
            return false
        }
        waiting.append(edit)
        self.shown = next
        wake?.yield()
        return true
    }

    /// Writes the waiting edits for as long as its task runs, and returns when it is cancelled. `prepare`
    /// may replace what a write sends just before it is sent (the builder reads the logged weeks again);
    /// what it throws fails the write as `update`'s error does.
    func run(
        prepare: @MainActor ([Edit]) async throws -> [Edit] = { $0 },
        finished: @MainActor (Outcome) -> Void
    ) async {
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        continuation.yield()
        for await _ in signals {
            await write(prepare: prepare, finished: finished)
        }
    }

    /// Writes until no edit waits, the program is gone, or the task is cancelled. One write runs at a time:
    /// a run that starts while an older one's write ends is woken by it.
    private func write(
        prepare: @MainActor ([Edit]) async throws -> [Edit],
        finished: @MainActor (Outcome) -> Void
    ) async {
        while !isWriting, let program = stored, !waiting.isEmpty, !Task.isCancelled {
            isWriting = true
            let sent = waiting.count
            defer { wake?.yield() }
            do {
                let edits = try await prepare(waiting)
                let saved = try await programs.update(program.id) { current in
                    try edits.reduce(current) { try $1.applied(to: $0) }
                }
                waiting.removeFirst(sent)
                heardDuringWrite = nil
                isWriting = false
                adopt(saved)
                finished(.stored)
            } catch is CancellationError where Task.isCancelled {
                isWriting = false
                adoptHeardDuringWrite()
                return
            } catch {
                waiting = []
                isWriting = false
                adoptHeardDuringWrite()
                redraw()
                finished(.failed(error))
            }
        }
    }

    private func adoptHeardDuringWrite() {
        if let heard = heardDuringWrite {
            heardDuringWrite = nil
            adopt(heard)
        }
    }

    private func adopt(_ program: Program?) {
        // Edits made on one program are never applied to another (the active program changed).
        if hasHeard, program?.id != stored?.id {
            waiting = []
        }
        stored = program
        hasHeard = true
        redraw()
    }

    private func redraw() {
        // An edit the stored program now refuses (the block got shorter elsewhere) is shown as nothing; the
        // write reports it, if it is still waiting then.
        shown = stored.map { stored in waiting.reduce(stored) { (try? $1.applied(to: $0)) ?? $0 } }
    }
}
