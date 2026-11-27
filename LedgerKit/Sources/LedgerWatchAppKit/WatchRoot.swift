import Foundation
import LedgerDesign
import SwiftUI
import WatchFeatureWorkout

/// The watch's root (F07): it renders the composition's state, the workout once the database is open (F18's
/// `WatchWorkoutRoot`, which opens on the screen before a workout) or product decision #29's screen, and runs the
/// launch's asynchronous part, then its retries on each return to the foreground. Its first appearance ends
/// launch-to-first-frame (#30). In Debug builds a long press on the screen's title opens the debug menu.
public struct WatchRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDebugMenuShown = false
    private let composition: WatchComposition

    public init(composition: WatchComposition) {
        self.composition = composition
    }

    public var body: some View {
        content
            .onAppear { composition.rootAppeared() }
            .task(id: scenePhase) {
                await composition.resume(in: scenePhase)
            }
    }

    @ViewBuilder private var content: some View {
        switch composition.state {
        case .ready:
            WatchWorkoutRoot(appName: Bundle.main.appName, health: composition.health) { isDebugMenuShown = true }
            #if DEBUG
                .sheet(isPresented: $isDebugMenuShown) {
                    DebugMenu { await composition.diagnostics() }
                }
            #endif
        case .databaseUnavailable:
            DatabaseUnavailableView()
        case .idle:
            LedgerColor.watchGround.ignoresSafeArea()
        }
    }
}

/// Product decision #29's screen: the database could not be opened.
struct DatabaseUnavailableView: View {
    var body: some View {
        ScrollView {
            EmptyState(WatchAppCopy.databaseUnavailableTitle, body: WatchAppCopy.databaseUnavailableBody)
        }
        .background(LedgerColor.watchGround)
    }
}

extension Bundle {
    /// The app's name as the watch's words write it ("Open %@ on iPhone"): `CFBundleDisplayName`, else
    /// `CFBundleName`, a blank one counting as absent, as the iPhone's About line reads it; no source names the
    /// product (product decisions › Naming).
    var appName: String {
        let names = ["CFBundleDisplayName", "CFBundleName"].compactMap { object(forInfoDictionaryKey: $0) as? String }
        return names.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}
