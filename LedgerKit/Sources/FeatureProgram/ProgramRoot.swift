import LedgerDesign
import SwiftUI

/// A week the app asks the builder to select (Today's "Edit week"). The number tells one request from the
/// next when both ask for the same week, so that a second request selects it again.
public nonisolated struct ProgramWeekRequest: Hashable, Sendable {
    public let number: Int
    /// The week's place in the block, 0 for the first.
    public let weekIndex: Int

    public init(number: Int, weekIndex: Int) {
        self.number = number
        self.weekIndex = weekIndex
    }
}

/// The Program builder in the app (F11 S13): the screen over its store. It owns the store and runs its work
/// from its tasks, the sources and the session's save loop, so nothing outlives the view; a write in flight
/// when the view goes away stores all of its edits or none, and the edits not stored are sent when it
/// comes back. The app hands it `onRoute`, which resolves where a tap goes (architecture §4), and the week
/// to select, when it asks for one.
///
/// **The sources are followed again when the app comes back from the background**, as `TodayRoot` follows
/// Today's: the task's id changes on the way there and on the way back, and at no other change of the scene's
/// phase, so the failed state's "Open the app again" is true. The save loop's task is not keyed: going to the
/// background never cancels a write. A view hosted with no scene is told it is in the background, and
/// follows nothing until its host says otherwise.
///
/// It draws the builder once the program is known, and a message when there is none or it cannot be read
/// (Pete's decision 6). The notice under the block is announced to VoiceOver when it appears or changes.
public struct ProgramRoot: View {
    @State private var store: ProgramStore
    @Environment(\.scenePhase) private var scenePhase
    private let week: ProgramWeekRequest?
    private let onRoute: @MainActor (ProgramRoute) -> Void
    private let announce: @MainActor (String) -> Void

    public init(week: ProgramWeekRequest? = nil, onRoute: @escaping @MainActor (ProgramRoute) -> Void) {
        self.init(store: ProgramStore(), week: week, onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows and hear what is announced. `@State` keeps
    /// the first store it is given: a store does no work when it is made.
    init(
        store: ProgramStore,
        week: ProgramWeekRequest? = nil,
        onRoute: @escaping @MainActor (ProgramRoute) -> Void,
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        _store = State(initialValue: store)
        self.week = week
        self.onRoute = onRoute
        self.announce = announce
    }

    public var body: some View {
        let state = store.state
        content(state)
            .task(id: scenePhase == .background) {
                guard scenePhase != .background else {
                    return
                }
                await store.run()
            }
            .task {
                await store.save()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
            .onChange(of: week, initial: true) { _, week in
                if let week {
                    store.select(request: week)
                }
            }
            .onChange(of: state.notice) { _, notice in
                if let notice {
                    announce(notice)
                }
            }
    }

    @ViewBuilder
    private func content(_ state: ProgramStore.State) -> some View {
        switch state {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case let .loaded(model):
            ProgramScreen(model: model, send: store.send)
        case .noProgram:
            ProgramMessage(title: ProgramCopy.noProgramTitle, text: ProgramCopy.noProgramBody)
        case .failed:
            ProgramMessage(title: ProgramCopy.failedTitle, text: ProgramCopy.failedBody)
        }
    }
}

/// A message in place of a Program screen, on the ground: the builder's when there is no program or it
/// cannot be read, and the Day editor's when it cannot be read (Pete's decision 6's texts).
struct ProgramMessage: View {
    let title: String
    let text: String

    var body: some View {
        EmptyState(title, body: text)
            .padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LedgerColor.ground)
    }
}

private extension ProgramStore.State {
    /// The notice's line, while the builder shows one.
    var notice: String? {
        if case let .loaded(model) = self {
            return model.notice
        }
        return nil
    }
}
