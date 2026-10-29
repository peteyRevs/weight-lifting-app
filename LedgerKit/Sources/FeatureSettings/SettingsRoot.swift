import LedgerDesign
import SwiftUI

/// Settings in the app (F14 S1), pushed on the stack of the tab whose gear opened it: the screen over its store. It
/// owns the store and runs its work from its tasks, so nothing outlives the view; the app hands it the About line's
/// values and `onRoute`, which resolves where "Diagnostics" goes (architecture §4).
///
/// **Until the settings are read** it draws the title alone, so the pushed screen is named from its first frame.
///
/// **A change is saved by the root's task** (`SettingsStore.run()`): one made as the lifter leaves the screen is
/// saved if its save has begun, as the exercise sheet's save is.
///
/// **A route is handed on once.** The screen's taps go to the store, which keeps one route waiting; the task below
/// hands it to the app and the store forgets it when the app's handler has returned.
///
/// **A failed save is announced** to VoiceOver when its line appears, since the line stands at the top of the page,
/// away from the focus (F14-S1b-2), as `ProgramRoot` announces its notice.
public struct SettingsRoot: View {
    @State private var store: SettingsStore
    private let onRoute: @MainActor (SettingsRoute) -> Void
    private let announce: @MainActor (String) -> Void

    public init(about: AppAbout, onRoute: @escaping @MainActor (SettingsRoute) -> Void) {
        self.init(store: SettingsStore(about: about), onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows and hear what is announced. `@State` keeps the
    /// first store it is given: a store does no work when it is made.
    init(
        store: SettingsStore,
        onRoute: @escaping @MainActor (SettingsRoute) -> Void,
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        _store = State(initialValue: store)
        self.onRoute = onRoute
        self.announce = announce
    }

    public var body: some View {
        content
            .task {
                await store.run()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
            .onChange(of: store.model?.problem) { _, problem in
                if let problem {
                    announce(problem)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let model = store.model {
            SettingsScreen(model: model, send: store.send)
        } else {
            SettingsHeader(title: SettingsCopy.title)
                .padding(LedgerSpacing.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(LedgerColor.ground)
        }
    }
}
