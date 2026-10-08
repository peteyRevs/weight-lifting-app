import LedgerDomain
import SwiftUI

public extension View {
    /// Presents the workout over this view: the full-screen cover, the "workout in progress" dialog and the
    /// alert of a start that failed, as `launcher` says, and runs the launcher's work. The app's root applies
    /// it once, above the tabs (architecture §4).
    ///
    /// `onRoute` is told why the cover closed, after it has closed.
    func workoutCover(
        _ launcher: WorkoutLauncher,
        onRoute: @escaping @MainActor (WorkoutRoute) -> Void = { _ in }
    ) -> some View {
        modifier(WorkoutCover(launcher: launcher, onRoute: onRoute))
    }
}

/// The launcher's three presentations, of which its `phase` shows at most one, and the task that answers
/// its requests. Each presentation is taken down by the launcher's state, never by the view.
struct WorkoutCover: ViewModifier {
    let launcher: WorkoutLauncher
    let onRoute: @MainActor (WorkoutRoute) -> Void

    private var conflict: WorkoutSource? {
        guard case let .conflict(source) = launcher.phase else {
            return nil
        }
        return source
    }

    private var failure: WorkoutAlertModel? {
        guard case let .failed(failure) = launcher.phase else {
            return nil
        }
        return WorkoutPresentation.alert(for: failure)
    }

    func body(content: Content) -> some View {
        let dialog = WorkoutPresentation.conflictDialog
        content
            .task(id: launcher.request) {
                await launcher.run()
            }
            .workoutCoverPresentation(isPresented: shows(launcher.phase == .cover, else: .coverClosed)) {
                WorkoutRoot { exit in
                    launcher.send(.coverClosed)
                    if case let .route(route) = exit {
                        onRoute(route)
                    }
                }
            }
            .confirmationDialog(
                dialog.title,
                isPresented: shows(conflict != nil, else: .cancelConflict),
                titleVisibility: .visible,
                presenting: conflict
            ) { source in
                Button(dialog.resume) { launcher.send(.resumeLive) }
                    .accessibilityIdentifier("workout.conflict.resume")
                Button(dialog.replace, role: .destructive) { launcher.send(.replaceLive(source)) }
                    .accessibilityIdentifier("workout.conflict.replace")
                // The cancelling role: the system decides how it is offered. From iOS 26 it draws no button
                // for it, and tapping outside the dialog cancels.
                Button(dialog.cancel, role: .cancel) { launcher.send(.cancelConflict) }
                    .accessibilityIdentifier("workout.conflict.cancel")
            }
            .alert(
                failure?.title ?? "",
                isPresented: shows(failure != nil, else: .dismissFailure),
                presenting: failure
            ) { failure in
                Button(failure.dismiss) { launcher.send(.dismissFailure) }
            } message: { failure in
                Text(failure.message)
            }
    }

    /// A presentation's flag. When the system takes the presentation down by itself, the launcher is sent
    /// `dismissal`, which is what its cancelling button sends.
    private func shows(_ isShown: Bool, else dismissal: WorkoutLaunchAction) -> Binding<Bool> {
        Binding {
            isShown
        } set: { isStillShown in
            if !isStillShown {
                launcher.send(dismissal)
            }
        }
    }
}

private extension View {
    /// A full-screen cover on the phone. The Mac host, which only builds this module for `swift test`, has
    /// none and gets a sheet.
    func workoutCoverPresentation(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        #if os(iOS)
            fullScreenCover(isPresented: isPresented, content: content)
        #else
            sheet(isPresented: isPresented, content: content)
        #endif
    }
}
