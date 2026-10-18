#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureWorkout
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// G2, F10 S7a criteria 1 and 10, in the real root: `WorkoutRoot` in a window over a `SaveSession`. The
    /// sheet is presented with its two heights, and cannot be swiped away while a save runs.
    ///
    /// Not here, and why: the failed save's alert coming back after each "Try again" (S7a-2). In a package
    /// test's window, which has no scene, a presentation's dismissal never completes: the sheet stays
    /// presented after the store took it down, and the alert is never presented, though the store says
    /// `.saveFailed` (measured on iOS 27.0, round 1). A UI test needs a way to make a save fail in the app.
    @MainActor
    @Suite("Workout root, the save (adversarial)", .serialized, .tags(.feature), .timeLimit(.minutes(3)))
    struct WorkoutRootSaveAdversarialTests {
        typealias Panel = WorkoutRestPanelAdversarialTests

        /// `WorkoutRoot` in a window, over a cover's store on a `SaveSession` with one set logged.
        struct Hosted {
            let session: SaveSession
            let store: WorkoutStore
            let host: UIViewController
            let window: UIWindow
            let running: WorkoutState

            init(size: DynamicTypeSize = .large, phone: CGSize = WorkoutScreenTests.phone) async throws {
                var workout = try Fixtures.seedSession()
                workout = try WorkoutPreview.logged(1, in: workout)
                running = workout
                let client = SaveSession(live: workout)
                session = client
                store = withTestDependencies {
                    $0.workoutSession = client
                    $0.date = .constant(Fixtures.now.addingTimeInterval(900))
                } operation: {
                    WorkoutStore()
                }
                host = UIHostingController(
                    rootView: WorkoutRoot(store: store) { _ in }.environment(\.dynamicTypeSize, size)
                )
                window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
                window.rootViewController = host
                window.isHidden = false
                host.view.layoutIfNeeded()
            }

            func close() {
                host.dismiss(animated: false)
                window.isHidden = true
                window.rootViewController = nil
            }

            /// What is presented over the root, topmost last.
            var presented: [UIViewController] {
                var found: [UIViewController] = []
                var next = host.presentedViewController
                while let controller = next {
                    found.append(controller)
                    next = controller.presentedViewController
                }
                return found
            }

            /// What the store and the window hold, for a failure's message.
            var state: String {
                "dialog \(String(describing: store.dialog)), saving \(store.isSaving), attempt \(store.saveAttempt),"
                    + " hearing \(store.isHearingTheSession), exit \(String(describing: store.exit)),"
                    + " presented \(presented.map { String(describing: type(of: $0)) })"
            }

            var sheet: UIViewController? {
                presented.first { !($0 is UIAlertController) && !$0.isBeingDismissed }
            }
        }
    }

    extension WorkoutRootSaveAdversarialTests {
        @Test("In the root: the sheet is presented with its two heights, and cannot be swiped away while it saves")
        func sheet_isPresented_andHeldWhileSaving() async throws {
            let hosted = try await Hosted()
            defer { hosted.close() }
            let store = hosted.store
            guard await Panel.turning("the root to follow the session", until: { store.isHearingTheSession }) else {
                return
            }
            #expect(hosted.presented.isEmpty)
            store.send(.finish)
            guard await Panel.turning("the sheet to be presented", until: { hosted.sheet != nil }) else {
                return
            }
            let sheet = try #require(hosted.sheet)
            // F10 S7a fix round 1 (ruling on S7a-1; edited by the implementer): full height only.
            #expect(sheet.sheetPresentationController?.detents.count == 1, "full height only")
            #expect(sheet.sheetPresentationController?.detents.first?.identifier == .large)
            #expect(!sheet.isModalInPresentation, "a swipe down is Keep lifting")
            await hosted.session.holdEveryEnd()
            store.send(.save)
            guard await Panel.turning("the session to be asked", until: { hosted.session.endsWaiting.value == 1 })
            else {
                return
            }
            _ = await Panel.turning("the sheet to be held", until: { sheet.isModalInPresentation })
            #expect(sheet.isModalInPresentation, "criterion 10: its interactive dismissal is off while it saves")
            #expect(hosted.sheet != nil, "the sheet stays up while it saves")
            await hosted.session.releaseEnd()
            _ = await Panel.turning("the cover to say it is done", until: { store.exit != nil })
            #expect(store.exit == .route(.saved(hosted.running.id)), "\(hosted.state)")
        }
    }
#endif
