import SwiftUI

/// Onboarding (F08; product spec §3.10, §6.7): three steps from nothing to a first program. The lifter picks a
/// goal and a number of days a week, sees the program that gives, and starts; or skips, and gets the default.
///
/// It has no route and makes no navigation call. Its one exit is the program it saves as the active one: the
/// app's root shows this screen while there is no active program and follows the stored program away from it.
///
/// `prepareRetry` is awaited before a save is tried again after a failure. The app passes the launch's seed
/// step: until the catalog is seeded a first save cannot succeed (product decision #28), and seeding is
/// otherwise retried only on the next return to the foreground.
///
/// **`prepareRetry` must return.** While it runs every control is disabled, nothing is saved, and the screen
/// offers no way to give up: only the view going away ends the wait. Pass a step that is bounded and that is
/// safe to run again (it runs once for each retry), as the launch's is; never one that can wait for ever.
public struct OnboardingRoot: View {
    @State private var store: OnboardingStore
    private let prepareRetry: @MainActor () async -> Void

    public init(prepareRetry: @escaping @MainActor () async -> Void = {}) {
        self.init(store: OnboardingStore(), prepareRetry: prepareRetry)
    }

    /// For the tests, which keep the store to send it what a tap sends. `@State` keeps the first store it is
    /// given: a store does no work when it is made.
    init(store: OnboardingStore, prepareRetry: @escaping @MainActor () async -> Void) {
        _store = State(initialValue: store)
        self.prepareRetry = prepareRetry
    }

    public var body: some View {
        OnboardingScreen(model: store.model, send: store.send)
            .task {
                await store.loadUnits()
            }
            .task(id: store.attempt) {
                await store.save(prepareRetry: prepareRetry)
            }
    }
}
